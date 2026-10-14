/**
 * Runs async tasks strictly one at a time, in submission order.
 *
 * This serialises file access *within one Node.js process*. It does not
 * coordinate separate processes or separate machines.
 */
export class SerialQueue {
  #tail = Promise.resolve();

  run(task) {
    const result = this.#tail.then(() => task());
    // Keep the chain alive even if this task fails.
    this.#tail = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }

  /** Resolves once every task queued so far (and any queued meanwhile) has settled. */
  async onIdle() {
    let current;
    do {
      current = this.#tail;
      await current;
    } while (current !== this.#tail);
  }
}
