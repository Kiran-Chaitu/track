/** Business logic: normalise, validate and persist registration numbers. */
export class RollNumberService {
  #storage;
  #normalize;

  constructor({ storage, normalizeRollNumber }) {
    this.#storage = storage;
    this.#normalize = normalizeRollNumber;
  }

  /**
   * @returns {Promise<{rollNumber: string, duplicate: boolean}>}
   * @throws {AppError} 400 for invalid input; StorageError for storage failures.
   */
  async register(rawValue) {
    const rollNumber = this.#normalize(rawValue);
    const { added } = await this.#storage.add(rollNumber);
    return { rollNumber, duplicate: !added };
  }

  list() {
    return this.#storage.list();
  }

  count() {
    return this.#storage.count();
  }

  checkStorageHealth() {
    return this.#storage.checkHealth();
  }
}
