import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const bucketName = "product-images";

type EdgeRuntimeGlobal = {
  EdgeRuntime?: {
    waitUntil: (promise: Promise<unknown>) => void;
  };
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const withoutBgKey = Deno.env.get("WITHOUTBG_API_KEY");

  if (!supabaseUrl || !serviceRoleKey || !withoutBgKey) {
    return json({ error: "Missing Supabase or withoutbg env vars" }, 500);
  }

  let productId = "";
  let imageUrl = "";

  try {
    const body = await req.json();
    productId = String(body.product_id ?? "");
    imageUrl = String(body.image_url ?? "");
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!productId || !imageUrl) {
    return json({ error: "product_id and image_url are required" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const work = processProductImage({
    supabase,
    withoutBgKey,
    productId,
    imageUrl,
  });

  const edgeRuntime = (globalThis as EdgeRuntimeGlobal).EdgeRuntime;
  if (edgeRuntime) {
    edgeRuntime.waitUntil(work);
    return json({ queued: true, product_id: productId }, 202);
  }

  await work;
  return json({ queued: true, product_id: productId }, 202);
});

async function processProductImage({
  supabase,
  withoutBgKey,
  productId,
  imageUrl,
}: {
  supabase: SupabaseClient;
  withoutBgKey: string;
  productId: string;
  imageUrl: string;
}) {
  await supabase
    .from("products")
    .update({ background_status: "processing", background_error: null })
    .eq("id", productId);

  try {
    const original = await fetch(imageUrl);
    if (!original.ok) {
      throw new Error(`Image fetch failed: ${original.status}`);
    }

    const form = new FormData();
    form.append("file", await original.blob(), `${productId}.jpg`);

    const removed = await fetch(
      "https://api.withoutbg.com/v1.0/image-without-background",
      {
        method: "POST",
        headers: { "X-API-Key": withoutBgKey },
        body: form,
      },
    );

    if (!removed.ok) {
      throw new Error(
        `withoutbg failed: ${removed.status} ${await removed.text()}`,
      );
    }

    const bytes = new Uint8Array(await removed.arrayBuffer());
    const storagePath = `cutouts/${productId}.png`;
    const uploaded = await supabase.storage
      .from(bucketName)
      .upload(storagePath, bytes, {
        contentType: "image/png",
        cacheControl: "31536000",
        upsert: true,
      });

    if (uploaded.error) {
      throw uploaded.error;
    }

    const { data } = supabase.storage.from(bucketName).getPublicUrl(storagePath);
    const cutoutUrl = data.publicUrl;

    const updated = await supabase
      .from("products")
      .update({
        original_image: imageUrl,
        cutout_image: cutoutUrl,
        outfit_images: [cutoutUrl],
        background_status: "completed",
        background_error: null,
      })
      .eq("id", productId);

    if (updated.error) {
      throw updated.error;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await supabase
      .from("products")
      .update({ background_status: "failed", background_error: message })
      .eq("id", productId);
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
