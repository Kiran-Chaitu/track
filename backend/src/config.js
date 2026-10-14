import path from 'node:path';
import { fileURLToPath } from 'node:url';

const BACKEND_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export const DEFAULT_ROLL_NUMBER_PATTERN = '^[A-Z0-9]{4,20}$';
export const DATA_FILE_NAME = 'roll_numbers.json';

export class ConfigError extends Error {}

function readInt(env, name, fallback, { min = 0, max = Number.MAX_SAFE_INTEGER } = {}) {
  const raw = env[name];
  if (raw === undefined || raw.trim() === '') return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ConfigError(`${name} must be an integer between ${min} and ${max}`);
  }
  return value;
}

function readBool(env, name, fallback) {
  const raw = env[name];
  if (raw === undefined || raw.trim() === '') return fallback;
  if (/^(1|true|yes)$/i.test(raw.trim())) return true;
  if (/^(0|false|no)$/i.test(raw.trim())) return false;
  throw new ConfigError(`${name} must be true or false`);
}

function readSecret(env, name) {
  const value = env[name]?.trim();
  return value ? value : null;
}

/**
 * Express "trust proxy" setting. Render terminates TLS at a single proxy hop,
 * so TRUST_PROXY=1 is correct there. Locally, leave it unset (false).
 */
function readTrustProxy(env) {
  const raw = env.TRUST_PROXY?.trim();
  if (!raw) return false;
  if (/^\d+$/.test(raw)) return Number(raw);
  if (/^(true|false)$/i.test(raw)) return raw.toLowerCase() === 'true';
  return raw; // e.g. "loopback" or a comma-separated subnet list
}

/**
 * Compiles the registration-number pattern. The pattern is always applied to
 * the whole value (it is wrapped in ^(?:...)$), so a pattern without anchors
 * cannot accidentally accept partial matches.
 */
export function compileRollNumberPattern(source) {
  try {
    return new RegExp(`^(?:${source})$`, 'u');
  } catch (err) {
    throw new ConfigError(`ROLL_NUMBER_PATTERN is not a valid regular expression: ${err.message}`);
  }
}

function resolveDataFilePath(env) {
  if (env.DATA_FILE_PATH?.trim()) return path.resolve(env.DATA_FILE_PATH.trim());
  if (env.DATA_DIR?.trim()) return path.resolve(env.DATA_DIR.trim(), DATA_FILE_NAME);
  return path.join(BACKEND_ROOT, 'data', DATA_FILE_NAME);
}

export function loadConfig(env = process.env) {
  const nodeEnv = env.NODE_ENV?.trim() || 'development';
  const isProduction = nodeEnv === 'production';
  const hasExplicitStorage = Boolean(env.DATA_FILE_PATH?.trim() || env.DATA_DIR?.trim());

  // In production the project directory is ephemeral on most hosts (including
  // Render without a disk). Refuse to silently store records there.
  if (isProduction && !hasExplicitStorage && !readBool(env, 'ALLOW_EPHEMERAL_STORAGE', false)) {
    throw new ConfigError(
      'DATA_FILE_PATH (or DATA_DIR) must point to persistent storage in production. ' +
        'Set ALLOW_EPHEMERAL_STORAGE=true only if losing data on restart is acceptable.',
    );
  }

  const rollNumberPatternSource = env.ROLL_NUMBER_PATTERN?.trim() || DEFAULT_ROLL_NUMBER_PATTERN;

  return Object.freeze({
    nodeEnv,
    isProduction,
    host: env.HOST?.trim() || '0.0.0.0',
    port: readInt(env, 'PORT', 3000, { min: 0, max: 65535 }),
    dataFilePath: resolveDataFilePath(env),
    rollNumberPatternSource,
    rollNumberPattern: compileRollNumberPattern(rollNumberPatternSource),
    // Hard upper bound applied before the pattern, whatever the pattern says.
    rollNumberMaxLength: readInt(env, 'ROLL_NUMBER_MAX_LENGTH', 64, { min: 1, max: 256 }),
    adminApiKey: readSecret(env, 'ADMIN_API_KEY'),
    ingestApiKey: readSecret(env, 'INGEST_API_KEY'),
    trustProxy: readTrustProxy(env),
    bodyLimit: env.BODY_LIMIT?.trim() || '1kb',
    requestTimeoutMs: readInt(env, 'REQUEST_TIMEOUT_MS', 10_000, { min: 100, max: 120_000 }),
    rateLimit: Object.freeze({
      windowMs: readInt(env, 'RATE_LIMIT_WINDOW_MS', 60_000, { min: 1000 }),
      // Several phones on one campus Wi-Fi share a NAT IP, so keep this generous.
      writeMax: readInt(env, 'RATE_LIMIT_WRITE_MAX', 300, { min: 1 }),
      adminMax: readInt(env, 'RATE_LIMIT_ADMIN_MAX', 30, { min: 1 }),
    }),
    logLevel: env.LOG_LEVEL?.trim() || (nodeEnv === 'test' ? 'silent' : 'info'),
  });
}
