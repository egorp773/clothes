import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const analyzerUrl = Deno.env.get("PRODUCT_ANALYZER_URL");
  const authorization = req.headers.get("Authorization");
  if (!supabaseUrl || !serviceRoleKey || !authorization) {
    return json({ error: "Missing Supabase or authorization env" }, 500);
  }

  let productId = "";
  try {
    const body = await req.json();
    productId = String(body.product_id ?? "");
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!productId) {
    return json({ error: "product_id is required" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const token = authorization.replace(/^Bearer\s+/i, "");
  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !authData.user) {
    return json({ error: "Invalid authorization" }, 401);
  }

  const { data: product, error: productError } = await supabase
    .from("products")
    .select("seller_id")
    .eq("id", productId)
    .maybeSingle();
  if (productError || !product) {
    return json({ error: "Product not found" }, 404);
  }
  if (product.seller_id !== authData.user.id) {
    return json({ error: "Only the product owner can process it" }, 403);
  }

  // Processing is durable in Postgres. The Edge function never downloads an
  // image or calls a model, so its lifetime cannot strand a published item.
  const { data: job, error: enqueueError } = await supabase.rpc(
    "enqueue_product_enrichment_job",
    {
      p_product_id: productId,
      p_reason: "edge_process_product_image",
      p_force: false,
    },
  );
  if (enqueueError) {
    return json({ error: enqueueError.message }, 500);
  }

  let workerWoken = false;
  if (analyzerUrl) {
    try {
      const response = await fetch(
        `${analyzerUrl.replace(/\/$/, "")}/v1/enrichment/wakeup`,
        {
          method: "POST",
          headers: { Authorization: authorization },
          signal: AbortSignal.timeout(3000),
        },
      );
      workerWoken = response.ok;
    } catch {
      // The worker polls the durable queue, so wake-up failure is harmless.
    }
  }

  return json(
    {
      queued: true,
      product_id: productId,
      job_id: typeof job === "string" ? job : null,
      worker_woken: workerWoken,
    },
    202,
  );
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
