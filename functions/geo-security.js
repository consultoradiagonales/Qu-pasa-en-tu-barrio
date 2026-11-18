// Elimina automáticamente reportes cuyas coordenadas caen fuera del
// bounding box de Argentina. Actúa como segunda línea de defensa tras
// las Firestore Security Rules.
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const AR_LAT_MIN = -55.1;
const AR_LAT_MAX = -21.8;
const AR_LNG_MIN = -73.6;
const AR_LNG_MAX = -53.6;

function insideArgentina(lat, lng) {
  return lat >= AR_LAT_MIN && lat <= AR_LAT_MAX &&
         lng >= AR_LNG_MIN && lng <= AR_LNG_MAX;
}

exports.blockForeignReports = onDocumentCreated(
  {
    document: 'reports/{reportId}',
    region: 'southamerica-east1',
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const lat = data?.location?.lat;
    const lng = data?.location?.lng;

    if (typeof lat !== 'number' || typeof lng !== 'number') return;
    if (insideArgentina(lat, lng)) return;

    const db = getFirestore();
    await db.collection('reports').doc(event.params.reportId).delete();

    await db.collection('security_events').add({
      type: 'foreign_report_blocked',
      reportId: event.params.reportId,
      userId: data.userId ?? null,
      lat,
      lng,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
);
