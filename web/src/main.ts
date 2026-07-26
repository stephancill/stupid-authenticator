import QRCode from "qrcode";
import { z } from "zod";
import "./style.css";

type Algorithm = "SHA1" | "SHA256" | "SHA512";

type Enrollment = {
  issuer: string;
  account: string;
  secret: string;
  algorithm: Algorithm;
  digits: number;
  period: number;
};

const enrollmentSchema = z.object({
  issuer: z.string().trim().min(1, "Issuer is required"),
  account: z.string().trim().min(1, "Account is required"),
  secret: z
    .string()
    .trim()
    .min(1, "Secret is required")
    .regex(/^[A-Z2-7]+=*$/i, "Secret must be Base32"),
  algorithm: z.enum(["SHA1", "SHA256", "SHA512"]),
  digits: z.coerce.number().int().min(6).max(8),
  period: z.coerce.number().int().min(15).max(120),
});

const base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

const app = document.querySelector<HTMLDivElement>("#app");

if (!app) {
  throw new Error("Missing #app element");
}

app.innerHTML = `
  <main class="shell">
    <section class="panel editor">
      <p class="eyebrow">Stupid Authenticator</p>
      <h1>TOTP enrollment tester</h1>
      <p class="intro">Generate a test enrollment QR code, scan it in the iOS app, and compare the live code below.</p>

      <form id="enrollment-form" class="form">
        <label>
          Issuer
          <input id="issuer" name="issuer" autocomplete="off" value="Stupid Test" />
        </label>
        <label>
          Account
          <input id="account" name="account" autocomplete="off" value="stephan@example.com" />
        </label>
        <label>
          Secret
          <div class="inline-field">
            <input id="secret" name="secret" autocomplete="off" spellcheck="false" />
            <button id="regenerate" type="button">New</button>
          </div>
        </label>
        <div class="grid">
          <label>
            Algorithm
            <select id="algorithm" name="algorithm">
              <option value="SHA1">SHA1</option>
              <option value="SHA256">SHA256</option>
              <option value="SHA512">SHA512</option>
            </select>
          </label>
          <label>
            Digits
            <select id="digits" name="digits">
              <option value="6">6</option>
              <option value="7">7</option>
              <option value="8">8</option>
            </select>
          </label>
          <label>
            Period
            <input id="period" name="period" type="number" min="15" max="120" step="1" value="30" />
          </label>
        </div>
      </form>
    </section>

    <section class="panel preview">
      <div class="qr-frame">
        <canvas id="qr" width="280" height="280" aria-label="Enrollment QR code"></canvas>
      </div>

      <div class="code-card">
        <span>Current code</span>
        <strong id="code">------</strong>
        <div class="countdown"><div id="bar"></div></div>
        <small id="remaining">30 seconds remaining</small>
      </div>

      <label class="url-label">
        otpauth URL
        <textarea id="url" readonly rows="4"></textarea>
      </label>

      <div class="actions">
        <button id="copy-url" type="button">Copy URL</button>
        <button id="copy-secret" type="button">Copy Secret</button>
      </div>

      <p id="error" class="error" role="alert"></p>
    </section>
  </main>
`;

const form = document.querySelector<HTMLFormElement>("#enrollment-form")!;
const qrCanvas = document.querySelector<HTMLCanvasElement>("#qr")!;
const codeEl = document.querySelector<HTMLElement>("#code")!;
const urlEl = document.querySelector<HTMLTextAreaElement>("#url")!;
const errorEl = document.querySelector<HTMLElement>("#error")!;
const remainingEl = document.querySelector<HTMLElement>("#remaining")!;
const barEl = document.querySelector<HTMLElement>("#bar")!;
const secretEl = document.querySelector<HTMLInputElement>("#secret")!;

secretEl.value = randomBase32Secret();

form.addEventListener("input", () => {
  void render();
});

document.querySelector<HTMLButtonElement>("#regenerate")!.addEventListener("click", () => {
  secretEl.value = randomBase32Secret();
  void render();
});

document.querySelector<HTMLButtonElement>("#copy-url")!.addEventListener("click", () => {
  void navigator.clipboard.writeText(urlEl.value);
});

document.querySelector<HTMLButtonElement>("#copy-secret")!.addEventListener("click", () => {
  void navigator.clipboard.writeText(secretEl.value);
});

setInterval(() => {
  void render();
}, 1000);

void render();

async function render() {
  const parsed = enrollmentSchema.safeParse(Object.fromEntries(new FormData(form)));

  if (!parsed.success) {
    errorEl.textContent = parsed.error.issues[0]?.message ?? "Invalid enrollment settings";
    codeEl.textContent = "------";
    return;
  }

  errorEl.textContent = "";
  const enrollment = parsed.data;
  const url = otpauthURL(enrollment);
  const code = await totp(enrollment, Date.now());
  const remaining = enrollment.period - (Math.floor(Date.now() / 1000) % enrollment.period);

  codeEl.textContent = groupCode(code);
  urlEl.value = url;
  remainingEl.textContent = `${remaining} second${remaining === 1 ? "" : "s"} remaining`;
  barEl.style.width = `${(remaining / enrollment.period) * 100}%`;

  await QRCode.toCanvas(qrCanvas, url, {
    margin: 2,
    scale: 8,
    color: {
      dark: "#111111",
      light: "#ffffff",
    },
  });
}

function otpauthURL(enrollment: Enrollment) {
  const label = `${enrollment.issuer}:${enrollment.account}`;
  const params = new URLSearchParams({
    secret: enrollment.secret.replaceAll("=", ""),
    issuer: enrollment.issuer,
    algorithm: enrollment.algorithm,
    digits: String(enrollment.digits),
    period: String(enrollment.period),
  });

  return `otpauth://totp/${encodeURIComponent(label)}?${params.toString()}`;
}

async function totp(enrollment: Enrollment, timestamp: number) {
  const keyData = base32Decode(enrollment.secret);
  const key = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: enrollment.algorithm.replace("SHA", "SHA-") },
    false,
    ["sign"],
  );
  const counter = Math.floor(timestamp / 1000 / enrollment.period);
  const counterBytes = new ArrayBuffer(8);
  new DataView(counterBytes).setBigUint64(0, BigInt(counter), false);
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, counterBytes));
  const offset = signature[signature.length - 1] & 0x0f;
  const binary =
    ((signature[offset] & 0x7f) << 24) |
    (signature[offset + 1] << 16) |
    (signature[offset + 2] << 8) |
    signature[offset + 3];
  const value = binary % 10 ** enrollment.digits;

  return value.toString().padStart(enrollment.digits, "0");
}

function randomBase32Secret() {
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  let bits = 0;
  let value = 0;
  let output = "";

  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;

    while (bits >= 5) {
      output += base32Alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }

  if (bits > 0) {
    output += base32Alphabet[(value << (5 - bits)) & 31];
  }

  return output;
}

function base32Decode(secret: string) {
  const cleaned = secret.toUpperCase().replaceAll("=", "").replaceAll(/\s/g, "");
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];

  for (const character of cleaned) {
    const index = base32Alphabet.indexOf(character);
    if (index === -1) {
      throw new Error("Invalid Base32 secret");
    }

    value = (value << 5) | index;
    bits += 5;

    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }

  return new Uint8Array(bytes);
}

function groupCode(code: string) {
  if (code.length !== 6) {
    return code;
  }

  return `${code.slice(0, 3)} ${code.slice(3)}`;
}
