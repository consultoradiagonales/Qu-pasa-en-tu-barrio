'use strict';

function countable(report) {
  return report && report.hidden !== true && report.municipalityId ? report : null;
}

function analyticsDelta(before, after) {
  const changes = {};
  const add = (key, delta) => {if (delta) changes[key] = (changes[key] || 0) + delta};
  for (const [report, sign] of [[before, -1], [after, 1]]) {
    if (!report) continue;
    add('total', sign);
    add('supports', sign * (Number(report.supportCount) || 0));
    if (['pending', 'assigned', 'in_progress', 'resolved', 'rejected', 'closed'].includes(report.status)) {
      add(`statusCounts.${report.status}`, sign);
    }
    if (['infrastructure', 'lighting', 'garbage', 'security', 'health', 'transport', 'environment', 'other'].includes(report.category)) {
      add(`categoryCounts.${report.category}`, sign);
    }
    if (report.resolvedAt && report.createdAt && typeof report.resolvedAt.toMillis === 'function' &&
        typeof report.createdAt.toMillis === 'function') {
      add('resolutionCount', sign);
      add('resolutionHoursSum', sign * Math.max(0,
          (report.resolvedAt.toMillis() - report.createdAt.toMillis()) / 3600000));
    }
  }
  return Object.fromEntries(Object.entries(changes).filter(([, value]) => value !== 0));
}

module.exports = {countable, analyticsDelta};
