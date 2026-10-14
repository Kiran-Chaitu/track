import { createHash, timingSafeEqual } from 'node:crypto';

import { sendError } from '../utils/http.js';

/** Constant-time comparison that does not leak the secret's length. */
function secretsMatch(provided, expected) {
  if (typeof provided !== 'string' || provided.length === 0) return false;
  const a = createHash('sha256').update(provided).digest();
  const b = createHash('sha256').update(expected).digest();
  return timingSafeEqual(a, b);
}

function bearerToken(req) {
  const header = req.get('authorization');
  const match = header?.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : undefined;
}

/**
 * Protects administrative endpoints with `Authorization: Bearer <ADMIN_API_KEY>`.
 * If no key is configured the endpoints are disabled rather than left open.
 */
export function requireAdmin(adminApiKey) {
  return (req, res, next) => {
    if (!adminApiKey) {
      return sendError(res, 503, 'ADMIN_DISABLED', 'Administrative access is not configured on this server');
    }
    if (!secretsMatch(bearerToken(req), adminApiKey)) {
      res.set('WWW-Authenticate', 'Bearer');
      return sendError(res, 401, 'UNAUTHORIZED', 'Valid administrator credentials are required');
    }
    return next();
  };
}

/**
 * Optional shared ingestion key sent by the mobile app as `X-Api-Key`.
 * Any key shipped inside a distributed app can be extracted, so this only
 * deters casual misuse; it is not strong authentication.
 */
export function requireIngestKey(ingestApiKey) {
  return (req, res, next) => {
    if (!ingestApiKey) return next();
    if (!secretsMatch(req.get('x-api-key'), ingestApiKey)) {
      return sendError(res, 401, 'UNAUTHORIZED', 'A valid API key is required');
    }
    return next();
  };
}
