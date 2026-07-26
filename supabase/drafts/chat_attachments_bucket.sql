-- STATUS: NOT YET APPLIED. Written 2026-07-26 during AMB.6.
--
-- Creates the storage bucket chat image and file messages need.
--
-- Why this does not already exist: ChatManager.uploadImage and uploadFile were
-- hard-coded to set an error and return nil, so the photo and file pickers in
-- the message composer have never done anything. The user still saw the
-- "Uploading..." overlay first. There is no chat bucket in either app — the web
-- app defines a 'chat-files' constant in src/supabase/storageService.js that
-- nothing imports, uploads to, or reads: three lines of dead configuration.
--
-- Shape follows 20260117_equipment_photos_bucket.sql in the web app's repo,
-- which is the pattern this project already trusts for a private bucket keyed on
-- a path prefix.
--
-- ONE DELIBERATE DIFFERENCE FROM THAT PATTERN, and it is the point of this file.
-- Equipment scopes on organization alone: first path segment = organization_id.
-- Copying that for chat would make every attachment in the company readable by
-- everyone in the company, including files posted in a private direct message
-- between two people. So the path carries the conversation as well —
--
--     {organization_id}/{conversation_id}/{uuid}.{ext}
--
-- and the read policy additionally requires that the caller is a PARTICIPANT of
-- that conversation, reusing the same jsonb containment expression as the
-- conversations RLS policy (participants @> auth.uid()) and the five chat RPCs.
-- A person removed from a group therefore loses access to that group's files,
-- which is the behaviour a reasonable person expects.
--
-- Blast radius on the SHARED database: additive only. A new bucket and four new
-- policies scoped to that bucket_id. Nothing existing is altered, and no other
-- bucket's policies are touched. The web app does not read or write chat
-- attachments today, so nothing there changes.
--
-- NOT DONE HERE, and named rather than left implicit: there is no size limit and
-- no MIME allowlist on the bucket. The client downsamples images to 2048px at
-- 0.8 quality (UIImage+Downsample, the app-wide standard) and the file picker is
-- restricted to pdf/text/data, but neither is a server-side control. Adding
-- file_size_limit and allowed_mime_types to the bucket is a follow-on worth
-- doing; it is called out so it is a decision rather than an oversight.

-- Create the bucket if it doesn't exist. Private, like equipment-photos.
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-attachments', 'chat-attachments', false)
ON CONFLICT (id) DO NOTHING;

-- Policy: a participant may upload into their own org + a conversation they are in.
-- users.id is TEXT, auth.uid() returns UUID, so cast to text.
CREATE POLICY "Participants can upload chat attachments"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'chat-attachments' AND
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()::text
    AND users.organization_id = (storage.foldername(name))[1]
  ) AND
  EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id = (storage.foldername(name))[2]
    AND c.participants @> to_jsonb((auth.uid())::text)
  )
);

-- Policy: a participant may read attachments from conversations they are in.
CREATE POLICY "Participants can view chat attachments"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'chat-attachments' AND
  EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id = (storage.foldername(name))[2]
    AND c.participants @> to_jsonb((auth.uid())::text)
  )
);

-- Policy: admins and managers of the owning org may delete.
-- Deliberately NOT "the uploader may delete": a message's attachment outliving
-- its message is the lesser problem, and chat has no delete-message path at all
-- (the messages table has no DELETE policy), so a self-serve delete here would
-- leave a message pointing at a missing file.
CREATE POLICY "Admins can delete chat attachments"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'chat-attachments' AND
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()::text
    AND users.role IN ('admin', 'manager')
    AND users.organization_id = (storage.foldername(name))[1]
  )
);

-- Policy: admins and managers of the owning org may update.
CREATE POLICY "Admins can update chat attachments"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'chat-attachments' AND
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()::text
    AND users.role IN ('admin', 'manager')
    AND users.organization_id = (storage.foldername(name))[1]
  )
);
