'use strict';
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { GoogleAuth } = require('google-auth-library');
const { generate, reserve, photoPath } = require('./report-ai');
const PROJECT = 'project-5fc9024a-e961-42b7-9ee';
const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });

exports.interpretCitizenReport = onDocumentCreated({
  document: 'reports/{reportId}', region: 'southamerica-east1',
  serviceAccount: `condi-ai@${PROJECT}.iam.gserviceaccount.com`,
  memory: '512MiB', timeoutSeconds: 90, maxInstances: 2, concurrency: 4, retry: true,
}, async event => {
  const report = event.data?.data();
  const id = event.params.reportId;
  if (!report || report.aiRequested !== true || report.aiConsentVersion !== 1 || report.hidden === true ||
      typeof report.userId !== 'string' || !report.userId || !Array.isArray(report.photosReport)) return;
  const db = getFirestore();
  const insight = db.collection('reportInsights').doc(id);
  if (!await reserve(db, id, report.userId)) return;
  try {
    const bucket = getStorage().bucket();
    const file = bucket.file(photoPath(report.photosReport[0], bucket.name, id));
    const [metadata] = await file.getMetadata();
    if (Number(metadata.size) > 4 * 1024 * 1024 || !['image/jpeg', 'image/png'].includes(metadata.contentType)) throw new Error('invalid_photo');
    // Read through authenticated Storage, never fetch a URL supplied by the app.
    const [photo] = await file.download();
    if (photo.length === 0 || photo.length > 4 * 1024 * 1024) throw new Error('invalid_photo');
    const token = await auth.getAccessToken();
    const result = await generate(report, photo, metadata.contentType, { project: PROJECT, token });
    // No changes to the citizen's category/comment or the municipal work state.
    await insight.set({ ...result, status: 'ready', generatedAt: FieldValue.serverTimestamp(), schemaVersion: 1 }, { merge: true });
  } catch (error) {
    const retryable = error.retryable === true || error.name === 'TimeoutError' || error.name === 'AbortError';
    await insight.set({ status: retryable ? 'retrying' : 'unavailable',
      reason: error.message?.startsWith('vertex_') ? error.message : 'interpretation_unavailable',
      updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    // Logs contain neither photos, user comments, contact details nor tokens.
    console.warn('ConDi AI unavailable', { reportId: id, retryable });
    if (retryable) throw new Error('retry_interpretation');
  }
});
