import { Router } from 'express';

/**
 * GET /api/health
 *
 * Always 200 while the process is running (so Render's health check reflects
 * process liveness). Storage health is reported separately in `storage`,
 * because a live process does not imply a usable data file.
 */
export function createHealthRouter({ service }) {
  const router = Router();

  router.get('/', async (_req, res) => {
    const storage = await service.checkStorageHealth();
    res.status(200).json({
      success: true,
      status: 'ok',
      uptimeSeconds: Math.round(process.uptime()),
      storage: storage.ok ? { status: 'ok' } : { status: 'error', code: storage.code },
    });
  });

  return router;
}
