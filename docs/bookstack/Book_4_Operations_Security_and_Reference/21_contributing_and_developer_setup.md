# Chapter 21: Contributing, Standards & Dev Setup

## 21.1 Development Environment Prerequisites

To contribute to Seraph Protocol, ensure your local development workstation is configured with the following toolchains:

1. **Foundry**: Ethereum smart contract development framework.
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```
2. **Rust & Cargo**: Latest stable toolchain (1.80+).
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```
3. **Node.js**: Modern JavaScript runtime (Node.js v20+ or v22+).
4. **Git**: Distributed version control system.

---

## 21.2 Repository Setup & Verification

Clone the monorepo and verify all build targets:

```bash
# Clone the repository
git clone https://github.com/seraphprotocol/seraph.git
cd seraph

# 1. Verify and compile Foundry smart contracts
export PATH="$HOME/.foundry/bin:$PATH"
forge build
forge test

# 2. Verify and compile the Rust base-layer node
cargo build --manifest-path base-layer/Cargo.toml
cargo test --manifest-path base-layer/Cargo.toml

# 3. Verify TypeScript SDK & UI test suites
node --test sdk/typescript/test/*.test.mjs
```

---

## 21.3 Coding Standards & Testing Requirements

All contributions to Seraph are evaluated against strict architectural guidelines:

### 1. Smart Contract Standards (Solidity)
- Use Solidity `^0.8.24` with EVM target `cancun`.
- Inherit from OpenZeppelin v5 contracts.
- All public external functions accepting external asset transfers must utilize `nonReentrant`.
- All fee claims and external transfers must follow the **pull-over-push** design pattern.
- Any new contract modification must include corresponding Foundry unit tests and fuzz invariant tests.

### 2. Base Layer Standards (Rust)
- Adhere to standard Rust formatting: `cargo fmt --check`.
- Zero warnings from `cargo clippy`.
- Any modification to cryptographic commitments or nullifier hashing must be accompanied by multi-asset isolation tests in `base-layer/tests/adversarial_pentest.rs`.

### 3. Frontend & SDK Standards (TypeScript & Web)
- Zero external runtime framework bloat where possible.
- All on-chain string data injected into the DOM must be sanitized via `lpEsc()` to prevent XSS vulnerabilities.
- Cryptographic keys must remain in memory as typed byte arrays (`Uint8Array`) and never logged to console or local storage unencrypted.

---

## 21.4 Submitting Pull Requests & Git Conventions

1. **Branch Naming**:
   - `feat/feature-name` for new protocol capabilities.
   - `fix/bug-description` for security or logic patches.
   - `docs/documentation-update` for documentation improvements.
2. **Commit Messages**: Follow the Conventional Commits specification:
   ```
   feat(core): add taxExempt mapping for DEX routers
   fix(pool): attach whenNotPaused to shield and unshield
   test(pentest): add multi-actor invariant tests for gas relayer
   docs(bookstack): add Chapter 18 on emergency procedures
   ```
3. **Pull Request Quality Gate**:
   - Every PR must pass all 155+ Foundry tests with 0 reverts.
   - Every PR must pass all 17 Rust base-layer pentests.
   - Every PR must pass all 43 Node.js verification tests.
   - Two approvals from core maintainers are required prior to merging into `main`.
