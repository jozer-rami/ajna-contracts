## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Cross-chain Randomness Example

This repository also contains two helper contracts that show how to request
random values between chains via LayerZero and the [Pyth entropy
service](https://docs.pyth.network/documentation/entropynet).

### Contracts

- `RandomProviderA` – deployed on the chain that has access to Pyth entropy.
  It receives requests from another chain, fetches randomness from the
  entropy service and sends the result back via LayerZero.
- `RandomRequestorB` – deployed on the requesting chain. It sends a message to
  the provider and stores the returned randomness.

Both contracts take the LayerZero endpoint address for their respective chains
as a constructor argument. Additionally, `RandomProviderA` is passed the Pyth
entropy contract address and the remote chain details.

### Expected LayerZero Chain IDs

LayerZero uses 16‑bit chain identifiers. Common ids are:

| Chain       | ID  |
|-------------|----:|
| Ethereum    | 101 |
| BNB Chain   | 102 |
| Avalanche   | 106 |

Check the official documentation for the full list. When deploying you must
provide the id of the remote chain so that both sides can communicate.

### Deploying Both Sides

1. Deploy `RandomProviderA` on the entropy enabled chain:

   ```solidity
   new RandomProviderA(
       <endpoint>,         // LayerZero endpoint
       <pyth_entropy>,     // Pyth entropy service
       <requestorChainId>, // uint16 id of the requesting chain
       abi.encodePacked(<requestorAddress>)
   );
   ```

2. Deploy `RandomRequestorB` on the requesting chain:

   ```solidity
   new RandomRequestorB(
       <endpoint>,         // LayerZero endpoint
       <providerChainId>,  // uint16 id of the provider chain
       abi.encodePacked(<providerAddress>)
   );
   ```

### Example Usage

Calling `requestRandom` on `RandomRequestorB` sends a message to the provider.
After LayerZero delivers the response, the randomness can be read from the
`randomResults` mapping or the `RandomReceived` event:

```solidity
RandomRequestorB requestor = RandomRequestorB(<address>);
requestor.requestRandom{value: msg.value}();
bytes32 value = requestor.randomResults(requestor.requestCount());
```

### Running Tests

Ensure submodules are initialised before testing:

```bash
git submodule update --init --recursive
```

Then run the forge test suite:

```bash
forge test
```
