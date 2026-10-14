import { rateLimit } from 'express-rate-limit';

import { sendError } from '../utils/http.js';

function createLimiter({ windowMs, limit }) {
  return rateLimit({
    windowMs,
    limit,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    handler: (_req, res) =>
      sendError(res, 429, 'RATE_LIMITED', 'Too many requests. Please wait a moment and try again.'),
  });
}

/** Per-IP limits. In-memory, so they apply per process (fine for one instance). */
export function createRateLimiters(rateLimitConfig) {
  return {
    write: createLimiter({ windowMs: rateLimitConfig.windowMs, limit: rateLimitConfig.writeMax }),
    admin: createLimiter({ windowMs: rateLimitConfig.windowMs, limit: rateLimitConfig.adminMax }),
  };
}
