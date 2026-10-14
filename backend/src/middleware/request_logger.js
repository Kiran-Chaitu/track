/** Logs method, path, status and duration. Bodies and query strings are never logged. */
export function requestLogger(logger) {
  return (req, res, next) => {
    const start = process.hrtime.bigint();
    res.once('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - start) / 1e6;
      logger.info('request', {
        method: req.method,
        // originalUrl keeps the mount prefix (/api/...); the query string is dropped.
        path: req.originalUrl.split('?')[0],
        status: res.statusCode,
        durationMs: Math.round(durationMs),
      });
    });
    next();
  };
}
