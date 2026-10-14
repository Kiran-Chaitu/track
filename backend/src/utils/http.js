/**
 * Sends a JSON response unless one was already sent (for example by the
 * request-timeout middleware), avoiding "headers already sent" errors.
 */
export function sendJson(res, status, body) {
  if (res.headersSent) return;
  res.status(status).json(body);
}

export function sendError(res, status, code, message) {
  sendJson(res, status, { success: false, code, message });
}
