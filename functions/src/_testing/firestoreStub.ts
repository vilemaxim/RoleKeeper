/**
 * Minimal in-memory Firestore stub for pure unit tests.
 *
 * Supports just enough of the Admin SDK surface for the LarpManager
 * player-sync pipeline: `db.doc(path).get()`, `db.collection(path).get()`,
 * `db.collection(path).where(...).where(...).limit(n).get()`,
 * `db.collection(path).doc(id)`, and `db.batch()` with `.set(ref, data, {merge})`.
 *
 * Not a general-purpose stub — only `==` filters and merge-set writes are
 * implemented because those are all the production code uses on these paths.
 */

export interface StubDocSeed {
  path: string;
  data: Record<string, unknown>;
}

export interface StubWrite {
  path: string;
  data: Record<string, unknown>;
  merge: boolean;
}

interface StubDocRef {
  _path: string;
  get(): Promise<{ exists: boolean; data: () => Record<string, unknown> | undefined }>;
  set(
    data: Record<string, unknown>,
    opts?: { merge?: boolean }
  ): Promise<void>;
}

interface StubQuerySnapshot {
  empty: boolean;
  size: number;
  docs: Array<{
    id: string;
    data: () => Record<string, unknown>;
    ref: StubDocRef;
  }>;
}

type Filter = readonly [string, string, unknown];

export interface FirestoreStub {
  db: {
    doc: (path: string) => StubDocRef;
    collection: (path: string) => StubCollectionRef;
    batch: () => StubBatch;
  };
  writes: StubWrite[];
  store: Map<string, Record<string, unknown>>;
}

/**
 * Optional hooks injected at construction time. `failOnGet` is invoked on
 * every `.get()` (both document and collection-query reads) — return an Error
 * to make that read reject, or `null` to let it proceed. Tests use this to
 * simulate degraded Firestore / failing sync attempts without touching HTTP.
 */
export interface FirestoreStubOptions {
  failOnGet?: (path: string, kind: "doc" | "collection") => Error | null;
}

interface StubCollectionRef {
  doc: (id: string) => StubDocRef;
  where: (field: string, op: string, val: unknown) => StubQuery;
  limit: (n: number) => StubQuery;
  get: () => Promise<StubQuerySnapshot>;
}

interface StubQuery {
  where: (field: string, op: string, val: unknown) => StubQuery;
  limit: (n: number) => StubQuery;
  get: () => Promise<StubQuerySnapshot>;
}

interface StubBatch {
  set: (
    ref: StubDocRef,
    data: Record<string, unknown>,
    opts?: { merge?: boolean }
  ) => void;
  delete: (ref: StubDocRef) => void;
  commit: () => Promise<void>;
}

export function makeFirestoreStub(
  seed: StubDocSeed[] = [],
  options: FirestoreStubOptions = {}
): FirestoreStub {
  const store = new Map<string, Record<string, unknown>>();
  for (const d of seed) store.set(d.path, { ...d.data });
  const writes: StubWrite[] = [];
  const failOnGet = options.failOnGet;

  const docRef = (path: string): StubDocRef => ({
    _path: path,
    async get() {
      if (failOnGet) {
        const err = failOnGet(path, "doc");
        if (err) throw err;
      }
      const data = store.get(path);
      return {
        exists: data !== undefined,
        data: () => data,
      };
    },
    async set(data, opts) {
      const merge = opts?.merge === true;
      if (merge) {
        const prev = store.get(path) ?? {};
        store.set(path, { ...prev, ...data });
      } else {
        store.set(path, { ...data });
      }
      writes.push({ path, data, merge });
    },
  });

  const applyQuery = (
    basePath: string,
    filters: readonly Filter[],
    limit: number | undefined
  ): StubQuerySnapshot => {
    const matching: StubQuerySnapshot["docs"] = [];
    for (const [k, v] of store.entries()) {
      if (!k.startsWith(basePath + "/")) continue;
      const tail = k.slice(basePath.length + 1);
      if (tail.includes("/")) continue;
      let ok = true;
      for (const [field, op, val] of filters) {
        if (op !== "==") throw new Error(`stub only supports '==' (got ${op})`);
        if ((v as Record<string, unknown>)[field] !== val) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      matching.push({ id: tail, data: () => v, ref: docRef(k) });
      if (limit !== undefined && matching.length >= limit) break;
    }
    return { empty: matching.length === 0, size: matching.length, docs: matching };
  };

  const maybeFailCollection = (path: string): void => {
    if (failOnGet) {
      const err = failOnGet(path, "collection");
      if (err) throw err;
    }
  };

  const query = (
    basePath: string,
    filters: readonly Filter[],
    limit?: number
  ): StubQuery => ({
    where: (field, op, val) =>
      query(basePath, [...filters, [field, op, val] as const], limit),
    limit: (n) => query(basePath, filters, n),
    get: async () => {
      maybeFailCollection(basePath);
      return applyQuery(basePath, filters, limit);
    },
  });

  const collectionRef = (path: string): StubCollectionRef => ({
    doc: (id: string) => docRef(`${path}/${id}`),
    where: (field, op, val) => query(path, [[field, op, val] as const]),
    limit: (n) => query(path, [], n),
    get: async () => {
      maybeFailCollection(path);
      return applyQuery(path, [], undefined);
    },
  });

  const batch = (): StubBatch => {
    type BatchOp =
      | { kind: "set"; path: string; data: Record<string, unknown>; merge: boolean }
      | { kind: "delete"; path: string };
    const ops: BatchOp[] = [];
    return {
      set(ref, data, opts) {
        ops.push({
          kind: "set",
          path: ref._path,
          data,
          merge: opts?.merge === true,
        });
      },
      delete(ref) {
        ops.push({ kind: "delete", path: ref._path });
      },
      async commit() {
        for (const op of ops) {
          if (op.kind === "delete") {
            store.delete(op.path);
            continue;
          }
          if (op.merge) {
            const prev = store.get(op.path) ?? {};
            store.set(op.path, { ...prev, ...op.data });
          } else {
            store.set(op.path, { ...op.data });
          }
          writes.push({ path: op.path, data: op.data, merge: op.merge });
        }
      },
    };
  };

  return {
    db: {
      doc: (p: string) => docRef(p),
      collection: (p: string) => collectionRef(p),
      batch,
    },
    writes,
    store,
  };
}

export interface CapturedLog {
  level: "info" | "warn" | "error";
  msg: string;
  meta: unknown;
}

/**
 * Run `body` with `firebase-functions` logger replaced by spies that push
 * into the returned array. Restores originals on exit even when `body` throws.
 */
export async function withCapturedLogs<T>(
  body: (logs: CapturedLog[]) => Promise<T>
): Promise<T> {
  const logs: CapturedLog[] = [];
  const fns = (await import("firebase-functions")).logger as unknown as {
    info: (...a: unknown[]) => void;
    warn: (...a: unknown[]) => void;
    error: (...a: unknown[]) => void;
  };
  const origInfo = fns.info;
  const origWarn = fns.warn;
  const origError = fns.error;
  fns.info = (msg: unknown, meta?: unknown) =>
    logs.push({ level: "info", msg: String(msg), meta });
  fns.warn = (msg: unknown, meta?: unknown) =>
    logs.push({ level: "warn", msg: String(msg), meta });
  fns.error = (msg: unknown, meta?: unknown) =>
    logs.push({ level: "error", msg: String(msg), meta });
  try {
    return await body(logs);
  } finally {
    fns.info = origInfo;
    fns.warn = origWarn;
    fns.error = origError;
  }
}
