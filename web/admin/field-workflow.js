// Reglas puras del trabajo de cuadrilla en el panel web.
//
// firestore.rules solo deja guardar avances o resolver un trabajo en curso
// cuando `assignedWorkerId` coincide con quien escribe. Estas funciones
// replican esa condición para no ofrecer (ni subir fotos para) acciones que
// el servidor va a rechazar.

export function canActOnFieldTask(report, uid) {
  if (!report || typeof uid !== 'string' || uid.length === 0) return false;
  if (report.status !== 'in_progress') return false;
  return typeof report.assignedWorkerId === 'string' && report.assignedWorkerId === uid;
}

export function canStartFieldTask(report, uid) {
  return Boolean(report) && report.status === 'assigned' && typeof uid === 'string' && uid.length > 0;
}

// Sube la evidencia, escribe el documento y, si la escritura falla, intenta
// borrar el archivo recién subido para no dejar fotos huérfanas en Storage.
// `verify` corre antes de subir: si devuelve un texto, se corta sin subir nada.
export async function runFieldEvidenceUpdate({ verify, upload, update, cleanup }) {
  if (verify) {
    const problem = await verify();
    if (problem) throw new Error(problem);
  }
  const uploaded = await upload();
  try {
    await update(uploaded);
  } catch (error) {
    let cleaned = false;
    if (cleanup) {
      try {
        await cleanup(uploaded);
        cleaned = true;
      } catch (_) {
        cleaned = false;
      }
    }
    const denied = error?.code === 'permission-denied' || /permission/i.test(String(error?.message || ''));
    const reason = denied
      ? 'No se pudo guardar: este trabajo ya no está a tu cargo o no tenés permiso para modificarlo.'
      : 'No se pudo guardar el cambio del trabajo. Probá de nuevo.';
    const suffix = cleaned ? ' La foto subida se descartó.' : ' La foto subida no pudo descartarse.';
    const wrapped = new Error(`${reason}${suffix}`);
    wrapped.cause = error;
    wrapped.photoCleaned = cleaned;
    throw wrapped;
  }
  return uploaded;
}
