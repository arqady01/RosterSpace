import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? "";

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return new Response("Supabase credentials missing", {
      status: 500,
      headers: corsHeaders,
    });
  }

  const authHeader = req.headers.get("Authorization") ?? "";

  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  const {
    data: { user },
    error: userError,
  } = await client.auth.getUser();

  if (userError || !user) {
    return new Response("Unauthorized", { status: 401, headers: corsHeaders });
  }

  let payload: AIChatPayload;
  try {
    payload = (await req.json()) as AIChatPayload;
  } catch (error) {
    console.error("Invalid request body", error);
    return new Response("Invalid JSON", { status: 400, headers: corsHeaders });
  }

  const { model_identifier, messages, client_message_id, attachments } =
    payload;

  const { data: config, error: configError } = await serviceClient
    .from("ai_model_configs")
    .select(
      "model_identifier, base_url, system_prompt, api_secret_name, display_name"
    )
    .eq("model_identifier", model_identifier)
    .eq("is_active", true)
    .maybeSingle();

  if (configError || !config) {
    console.error("Model config not found", configError);
    return new Response("Model not available", {
      status: 404,
      headers: corsHeaders,
    });
  }

  const apiKey = Deno.env.get(config.api_secret_name);

  if (!apiKey) {
    console.error("Missing secret", config.api_secret_name);
    return new Response("Model secret not configured", {
      status: 500,
      headers: corsHeaders,
    });
  }

  const openai = new OpenAI({
    apiKey,
    baseURL: config.base_url,
  });

  const startTime = performance.now();

  const stream = await openai.chat.completions.create({
    model: config.model_identifier,
    stream: true,
    messages: [
      { role: "system", content: config.system_prompt },
      ...messages,
    ],
    metadata: {
      client_message_id,
      model_display_name: config.display_name,
      attachments,
    },
  });

  let latestUsage:
    | {
        prompt_tokens?: number;
        completion_tokens?: number;
        total_tokens?: number;
      }
    | undefined;

  const encoder = new TextEncoder();

  const responseStream = new ReadableStream({
    async start(controller) {
      try {
        for await (const chunk of stream) {
          if (chunk.usage) {
            latestUsage = chunk.usage;
          }

          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify(chunk)}\n\n`)
          );
        }

        controller.enqueue(encoder.encode("data: [DONE]\n\n"));
        controller.close();

        await serviceClient.from("ai_usage_logs").insert({
          user_id: user.id,
          model_identifier,
          request_id: client_message_id,
          status: "success",
          prompt_tokens: latestUsage?.prompt_tokens ?? null,
          completion_tokens: latestUsage?.completion_tokens ?? null,
          total_tokens: latestUsage?.total_tokens ?? null,
          latency_ms: Math.round(performance.now() - startTime),
        });
      } catch (error) {
        console.error("Streaming error", error);
        controller.error(error);

        await serviceClient.from("ai_usage_logs").insert({
          user_id: user.id,
          model_identifier,
          request_id: client_message_id,
          status: "error",
          error_code: error?.code ?? null,
          error_message: error?.message ?? String(error),
          latency_ms: Math.round(performance.now() - startTime),
        });
      }
    },

    async cancel() {
      await serviceClient.from("ai_usage_logs").insert({
        user_id: user.id,
        model_identifier,
        request_id: client_message_id,
        status: "cancelled",
        latency_ms: Math.round(performance.now() - startTime),
      });
    },
  });

  return new Response(responseStream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-store",
      Connection: "keep-alive",
    },
  });
});

type AIChatPayload = {
  model_identifier: string;
  messages: Array<{
    role: "system" | "user" | "assistant";
    content:
      | string
      | Array<{
          type: "text" | "image_url";
          text?: string;
          image_url?: { url: string };
        }>;
  }>;
  client_message_id: string;
  attachments: Array<{
    type: string;
    url: string;
    contentType: string;
  }>;
};
