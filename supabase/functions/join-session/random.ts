/**
 * Random helpers built on the Web Crypto API (a CSPRNG). Math.random() is not
 * used anywhere here.
 */

/** Same human-friendly alphabet as invite codes (no 0/O/1/I). */
export const RECOVERY_CODE_CHARSET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const RECOVERY_CODE_GROUPS = 3;
const RECOVERY_CODE_GROUP_LENGTH = 4;

const BROWSER_TOKEN_BYTES = 32; // 256 bits

const UINT32_RANGE = 0x1_0000_0000; // 2^32

/** Uniform integer in [0, maxExclusive) using rejection sampling (no modulo bias). */
function randomInt(maxExclusive: number): number {
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

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** UUID v4 used as public.participants.id */
export function generateParticipantId(): string {
  return crypto.randomUUID();
}

/** BT_<43 base64url chars>: 256 random bits, kept by the browser as the participant's credential. */
export function generateBrowserToken(): string {
  const bytes = new Uint8Array(BROWSER_TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  return `BT_${toBase64Url(bytes)}`;
}

/** XXXX-XXXX-XXXX (60 bits), easy to write down and type on another device. */
export function generateRecoveryCode(): string {
  const groups: string[] = [];
  for (let g = 0; g < RECOVERY_CODE_GROUPS; g++) {
    let group = "";
    for (let i = 0; i < RECOVERY_CODE_GROUP_LENGTH; i++) {
      group += RECOVERY_CODE_CHARSET[randomInt(RECOVERY_CODE_CHARSET.length)];
    }
    groups.push(group);
  }
  return groups.join("-");
}
