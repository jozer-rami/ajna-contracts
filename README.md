# Ajna Oracle Contracts

This repository contains Solidity contracts developed with [Foundry](https://book.getfoundry.sh/) and a suite of unit tests. The main contract, **AJNAOracle**, implements an ERC‑721 NFT used to mint "revelation" tokens through signed vouchers or whitelisted addresses.

## Contracts

- `src/AjnaOracle.sol` – core NFT contract with role based access control, voucher redemption and whitelist minting.
- `src/RandomProviderA.sol` and `src/RandomRequestorB.sol` – example contracts demonstrating cross‑chain randomness requests via LayerZero and the Pyth entropy service.
- `src/Counter.sol` – minimal example contract.

## Running Tests

The `test` directory provides Foundry tests covering the `AJNAOracle` functionality. After cloning the repository and initialising submodules, run:

```bash
forge test
```

## Building

Compile all contracts with:

```bash
forge build
```

## Deployment

`AJNAOracle` is deployed on **World Chain** and verified on Blockscout at:

```
0xC72F8B1148D0d67397F543b37bedE31cf167D71D
```

Deployment scripts for the randomness example reside in `script/RandomDeployer.s.sol`.
