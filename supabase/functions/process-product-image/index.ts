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
  const analyzerUrl = Deno.env.get("PRODUCT_ANALYZER_URL");
  const authorization = req.headers.get("Authorization");

  if (!supabaseUrl || !serviceRoleKey || !analyzerUrl || !authorization) {
    return json({ error: "Missing Supabase, analyzer, or authorization env" }, 500);
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
    .select("seller_id,main_image,original_image,image")
    .eq("id", productId)
    .maybeSingle();
  if (productError || !product) {
    return json({ error: "Product not found" }, 404);
  }
  if (product.seller_id !== authData.user.id) {
    return json({ error: "Only the product owner can process its image" }, 403);
  }
  const imageUrl = [product.original_image, product.main_image, product.image]
    .map((value) => String(value ?? "").trim())
    .find((value) => value.length > 0) ?? "";
  if (!imageUrl.startsWith(`${supabaseUrl}/storage/v1/object/`)) {
    return json({ error: "Product image must be in project storage" }, 422);
  }

  const work = processProductImage({
    supabase,
    analyzerUrl,
    authorization,
    productId,
    imageUrl,
    ownerId: authData.user.id,
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
  analyzerUrl,
  authorization,
  productId,
  imageUrl,
  ownerId,
}: {
  supabase: SupabaseClient;
  analyzerUrl: string;
  authorization: string;
  productId: string;
  imageUrl: string;
  ownerId: string;
}) {
  await supabase
    .from("products")
    .update({ background_status: "processing", background_error: null })
    .eq("id", productId)
    .eq("seller_id", ownerId);

  try {
    const original = await fetch(imageUrl);
    if (!original.ok) {
      throw new Error(`Image fetch failed: ${original.status}`);
    }
    const advertisedSize = Number(original.headers.get("content-length") ?? 0);
    if (advertisedSize > 15 * 1024 * 1024) {
      throw new Error("Image is larger than 15 MB");
    }
    const originalBlob = await original.blob();
    if (originalBlob.size > 15 * 1024 * 1024) {
      throw new Error("Image is larger than 15 MB");
    }

    const form = new FormData();
    form.append("file", originalBlob, `${productId}.jpg`);

    const removed = await fetch(
      `${analyzerUrl.replace(/\/$/, "")}/v1/remove-background`,
      {
        method: "POST",
        headers: { Authorization: authorization },
        body: form,
      },
    );

    if (!removed.ok) {
      throw new Error(
        `background removal failed: ${removed.status}`,
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
      .eq("id", productId)
      .eq("seller_id", ownerId);

    if (updated.error) {
      throw updated.error;
    }

    const reindexed = await fetch(
      `${analyzerUrl.replace(/\/$/, "")}/v1/products/${productId}/embeddings`,
      {
        method: "POST",
        headers: { Authorization: authorization },
      },
    );
    if (!reindexed.ok) {
      console.error(
        `visual reindex failed for ${productId}: ${reindexed.status}`,
      );
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await supabase
      .from("products")
      .update({ background_status: "failed", background_error: message })
      .eq("id", productId)
      .eq("seller_id", ownerId);
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
