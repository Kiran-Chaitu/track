import { sendError } from '../utils/http.js';

/**
 * Responds with 503 if a handler has not answered within `ms`.
 *
 * The underlying work is not cancelled: a slow write may still complete after
 * the timeout response. Submissions are idempotent (re-sending a stored number
 * returns `duplicate: true`), so clients can safely retry.
 */
export function requestTimeout(ms) {
  return (_req, res, next) => {
    const timer = setTimeout(() => {
      sendError(res, 503, 'REQUEST_TIMEOUT', 'The server took too long to respond. Please try again.');
    }, ms);
    const clear = () => clearTimeout(timer);
    res.once('finish', clear);
    res.once('close', clear);
    next();
  };
}
