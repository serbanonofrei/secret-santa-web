/**
 * Random helpers built on the Web Crypto API (a CSPRNG). Math.random() is not
 * used anywhere here.
 */

export const INVITE_CODE_CHARSET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
export const INVITE_CODE_LENGTH = 6;

const UINT32_RANGE = 0x1_0000_0000; // 2^32

/**
 * Returns a uniformly distributed integer in [0, maxExclusive).
 * Rejection sampling avoids modulo bias.
 */
export function randomInt(maxExclusive: number): number {
  if (!Number.isInteger(maxExclusive) || maxExclusive <= 0 || maxExclusive > UINT32_RANGE) {
    throw new RangeError(`maxExclusive must be an integer in (0, 2^32], got ${maxExclusive}`);
  }

  const limit = UINT32_RANGE - (UINT32_RANGE % maxExclusive);
  const buffer = new Uint32Array(1);

  while (true) {
    crypto.getRandomValues(buffer);
    const value = buffer[0];
    if (value < limit) {
      return value % maxExclusive;
    }
  }
}

/** ORG_<uuid v4> */
export function generateOrganizerToken(): string {
  return `ORG_${crypto.randomUUID()}`;
}

/** 6 characters from INVITE_CODE_CHARSET (no 0/O/1/I to avoid confusion). */
export function generateInviteCode(length: number = INVITE_CODE_LENGTH): string {
  let code = "";
  for (let i = 0; i < length; i++) {
    code += INVITE_CODE_CHARSET[randomInt(INVITE_CODE_CHARSET.length)];
  }
  return code;
}

/**
 * Picks `count` distinct elements at random (partial Fisher-Yates shuffle).
 * The input array is not modified.
 */
export function pickRandom<T>(items: readonly T[], count: number): T[] {
  if (!Number.isInteger(count) || count < 0 || count > items.length) {
    throw new RangeError(`count must be an integer in [0, ${items.length}], got ${count}`);
  }

  const pool = [...items];
  for (let i = 0; i < count; i++) {
    const j = i + randomInt(pool.length - i);
    const tmp = pool[i];
    pool[i] = pool[j];
    pool[j] = tmp;
  }
  return pool.slice(0, count);
}
