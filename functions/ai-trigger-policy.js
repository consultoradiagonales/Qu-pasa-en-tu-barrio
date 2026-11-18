'use strict';

function shouldInterpret(before, report) {
  if (!report || report.aiRequested !== true || report.aiConsentVersion !== 1 ||
      report.hidden === true || report.photoUploadStatus === 'pending' ||
      typeof report.userId !== 'string' || !report.userId ||
      !Array.isArray(report.photosReport) ||
      typeof report.photosReport[0] !== 'string') return false;
  return !before || before.photoUploadStatus === 'pending';
}

module.exports = { shouldInterpret };
