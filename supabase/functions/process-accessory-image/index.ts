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

  let accessoryId = "";

  try {
    const body = await req.json();
    accessoryId = String(body.accessory_id ?? "");
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!accessoryId) {
    return json({ error: "accessory_id is required" }, 400);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const token = authorization.replace(/^Bearer\s+/i, "");
  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  if (authError || !authData.user) {
    return json({ error: "Invalid authorization" }, 401);
  }
  const { data: accessory, error: accessoryError } = await supabase
    .from("outfit_accessories")
    .select("owner_id,original_image,scope")
    .eq("id", accessoryId)
    .maybeSingle();
  if (accessoryError || !accessory) {
    return json({ error: "Accessory not found" }, 404);
  }
  if (!accessory.owner_id || accessory.owner_id !== authData.user.id) {
    return json({ error: "Only the accessory owner can process its image" }, 403);
  }
  const imageUrl = String(accessory.original_image ?? "");
  if (!imageUrl.startsWith(`${supabaseUrl}/storage/v1/object/`)) {
    return json({ error: "Accessory image must be in project storage" }, 422);
  }

  const work = processAccessoryImage({
    supabase,
    analyzerUrl,
    authorization,
    accessoryId,
    imageUrl,
    ownerId: String(accessory.owner_id),
  });

  const edgeRuntime = (globalThis as EdgeRuntimeGlobal).EdgeRuntime;
  if (edgeRuntime) {
    edgeRuntime.waitUntil(work);
    return json({ queued: true, accessory_id: accessoryId }, 202);
  }

  await work;
  return json({ queued: true, accessory_id: accessoryId }, 202);
});

async function processAccessoryImage({
  supabase,
  analyzerUrl,
  authorization,
  accessoryId,
  imageUrl,
  ownerId,
}: {
  supabase: SupabaseClient;
  analyzerUrl: string;
  authorization: string;
  accessoryId: string;
  imageUrl: string;
  ownerId: string;
}) {
  await supabase
    .from("outfit_accessories")
    .update({ background_status: "processing", background_error: null })
    .eq("id", accessoryId)
    .eq("owner_id", ownerId);

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
    form.append("file", originalBlob, `${accessoryId}.jpg`);

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
    const storagePath = `accessory-cutouts/${accessoryId}.png`;
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
      .from("outfit_accessories")
      .update({
        original_image: imageUrl,
        cutout_image: cutoutUrl,
        background_status: "completed",
        background_error: null,
      })
      .eq("id", accessoryId)
      .eq("owner_id", ownerId);

    if (updated.error) {
      throw updated.error;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await supabase
      .from("outfit_accessories")
      .update({ background_status: "failed", background_error: message })
      .eq("id", accessoryId)
      .eq("owner_id", ownerId);
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
