import { Router } from 'express';

import { requireAdmin, requireIngestKey } from '../middleware/auth.js';

export function createRollNumberRouter({ controller, config, limiters }) {
  const router = Router();
  const admin = [limiters.admin, requireAdmin(config.adminApiKey)];

  router.post('/', limiters.write, requireIngestKey(config.ingestApiKey), controller.create);
  router.get('/', ...admin, controller.list);
  router.get('/count', ...admin, controller.count);

  return router;
}
