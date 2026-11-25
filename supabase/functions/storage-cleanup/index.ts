// Deletes photo files left behind when someone leaves or is removed from a trip, or a trip is
// deleted. Those actions queue folders in `public.storage_cleanup` (migration 0003); this works
// through the queue with the service key, which is allowed to delete anyone's files.
//
// Runs every 10 minutes from pg_cron, and the app also calls it straight after leaving, removing
// someone or deleting a trip so the files usually go at once. It needs no caller identity: it can
// only delete files that are queued, older than their queue entry, and no longer used by any photo
// or cover, so calling it early or often does no harm.
//
// Deploy: supabase functions deploy storage-cleanup --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const BUCKET = "trip-photos";
/** Files per Storage API call (the API takes up to 1000). */
const BATCH = 500;
/** Stops one run from going on forever if deletes keep failing. */
const MAX_ROUNDS = 20;

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  let deleted = 0;
  for (let round = 0; round < MAX_ROUNDS; round++) {
    const { data, error } = await supabase.rpc("storage_cleanup_files", { p_limit: BATCH });
    if (error) return json({ error: error.message, deleted }, 500);
    const names = (data as { name: string }[]).map((row) => row.name);
    if (names.length === 0) break;

    const { data: removed, error: removeError } = await supabase.storage.from(BUCKET).remove(names);
    if (removeError) return json({ error: removeError.message, deleted }, 500);
    deleted += removed?.length ?? 0;
    // Nothing removed means these files can't be deleted right now; try again next run
    // rather than asking for the same batch over and over.
    if (!removed?.length) break;
  }

  const { data: finished, error: finishError } = await supabase.rpc("storage_cleanup_finish");
  if (finishError) return json({ error: finishError.message, deleted }, 500);
  return json({ deleted, foldersDone: finished });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
