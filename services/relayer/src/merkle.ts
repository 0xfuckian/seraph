import { toBuffer32, hashSortedPair } from "./crypto.ts";
import type { HasherType } from "./types.ts";

/**
 * Depth-appropriate binary Merkle tree with sorted-pair hashing
 * Compatible with OpenZeppelin MerkleProof and Seraph CrossEVMBridge.sol
 */
export class MerkleTree {
  private readonly leaves: Uint8Array[];
  private readonly layers: Uint8Array[][];
  private readonly hasher: HasherType;

  constructor(leaves: (Uint8Array | string)[], hasher: HasherType = "keccak256") {
    this.hasher = hasher;
    this.leaves = leaves.map((l) => new Uint8Array(toBuffer32(l)));
    this.layers = this.buildLayers();
  }

  private buildLayers(): Uint8Array[][] {
    if (this.leaves.length === 0) {
      return [[new Uint8Array(32)]];
    }

    const layers: Uint8Array[][] = [[...this.leaves]];

    while (layers[layers.length - 1].length > 1) {
      const current = layers[layers.length - 1];
      const next: Uint8Array[] = [];

      for (let i = 0; i < current.length; i += 2) {
        if (i + 1 < current.length) {
          next.push(hashSortedPair(current[i], current[i + 1], this.hasher));
        } else {
          // Promote odd orphan leaf to next layer
          next.push(current[i]);
        }
      }
      layers.push(next);
    }

    return layers;
  }

  /**
   * Returns the Merkle tree root hash
   */
  public getRoot(): Uint8Array {
    if (this.layers.length === 0 || this.layers[0].length === 0) {
      return new Uint8Array(32);
    }
    return this.layers[this.layers.length - 1][0];
  }

  /**
   * Returns the 0x-prefixed hex string of the root
   */
  public getRootHex(): string {
    return "0x" + Buffer.from(this.getRoot()).toString("hex");
  }

  /**
   * Returns the leaf count
   */
  public get leafCount(): number {
    return this.leaves.length;
  }

  /**
   * Returns copy of the normalized leaves
   */
  public getLeaves(): Uint8Array[] {
    return this.leaves.map((l) => new Uint8Array(l));
  }

  /**
   * Returns copy of the normalized leaves in hex format
   */
  public getLeavesHex(): string[] {
    return this.leaves.map((l) => "0x" + Buffer.from(l).toString("hex"));
  }

  /**
   * Generates Merkle inclusion proof for a leaf at a given index
   */
  public getProof(index: number): Uint8Array[] {
    if (index < 0 || index >= this.leaves.length) {
      throw new Error(`Leaf index ${index} out of range [0, ${this.leaves.length - 1}]`);
    }

    const proof: Uint8Array[] = [];
    let idx = index;

    for (let i = 0; i < this.layers.length - 1; i++) {
      const layer = this.layers[i];
      const isRight = idx % 2 === 1;
      const pairIdx = isRight ? idx - 1 : idx + 1;

      if (pairIdx < layer.length) {
        proof.push(new Uint8Array(layer[pairIdx]));
      }
      idx = Math.floor(idx / 2);
    }

    return proof;
  }

  /**
   * Generates Merkle inclusion proof in 0x-prefixed hex strings
   */
  public getProofHex(index: number): string[] {
    return this.getProof(index).map((p) => "0x" + Buffer.from(p).toString("hex"));
  }

  /**
   * Generates proof for a leaf by finding its value
   */
  public getProofForLeaf(leaf: Uint8Array | string): Uint8Array[] {
    const target = toBuffer32(leaf);
    const index = this.leaves.findIndex((l) => Buffer.compare(Buffer.from(l), target) === 0);
    if (index === -1) {
      throw new Error(`Leaf ${Buffer.from(target).toString("hex")} not found in tree`);
    }
    return this.getProof(index);
  }

  /**
   * Verifies a Merkle inclusion proof against a specified root
   */
  public static verify(
    leaf: Uint8Array | string,
    proof: (Uint8Array | string)[],
    root: Uint8Array | string,
    hasher: HasherType = "keccak256"
  ): boolean {
    const leafBuf = toBuffer32(leaf);
    const rootBuf = toBuffer32(root);

    let computed = new Uint8Array(leafBuf);
    for (const elem of proof) {
      const elemBuf = toBuffer32(elem);
      computed = hashSortedPair(computed, elemBuf, hasher);
    }

    return Buffer.compare(Buffer.from(computed), rootBuf) === 0;
  }
}
