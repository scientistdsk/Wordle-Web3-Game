import { vi } from 'vitest';
import { generateMockAddress, hbarToWei } from './test-helpers';
 
/**
 * Mock Wallet for Testing
 * Simulates window.ethereum and wallet interactions
 */

export interface MockWalletState {
  address: string | null;
  chainId: string;
  balance: bigint;
  isConnected: boolean;
}

export class MockWallet {
  private state: MockWalletState;
  private listeners: Map<string, Set<Function>>;

  constructor(initialState?: Partial<MockWalletState>) {
    this.state = {
      address: null,
      chainId: '0x128', // 296 in hex (Hedera Testnet)
      balance: hbarToWei(100),
      isConnected: false,
      ...initialState,
    };
    this.listeners = new Map();
  }

  // Mock window.ethereum methods
  request = vi.fn().mockImplementation(async ({ method, params }: any) => {
    switch (method) {
      case 'eth_requestAccounts':
        return this.connect();

      case 'eth_accounts':
        return this.state.isConnected && this.state.address
          ? [this.state.address]
          : [];

      case 'eth_chainId':
        return this.state.chainId;

      case 'eth_getBalance':
        return '0x' + this.state.balance.toString(16);

      case 'eth_sendTransaction':
        return this.sendTransaction(params[0]);

      case 'wallet_switchEthereumChain':
        return this.switchChain(params[0].chainId);

      case 'personal_sign':
        return this.signMessage(params[0]);

      case 'eth_estimateGas':
        return '0x' + BigInt(100000).toString(16);

      case 'eth_gasPrice':
        return '0x' + BigInt(1000000000).toString(16); // 1 gwei

      case 'eth_getTransactionReceipt':
        return {
          status: '0x1',
          transactionHash: params[0],
          blockNumber: '0x' + Math.floor(Math.random() * 1000000).toString(16),
        };

      default:
        throw new Error(`Unsupported method: ${method}`);
    }
  });

  on = vi.fn().mockImplementation((event: string, handler: Function) => {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set());
    }
    this.listeners.get(event)!.add(handler);
  });

  removeListener = vi.fn().mockImplementation((event: string, handler: Function) => {
    const handlers = this.listeners.get(event);
    if (handlers) {
      handlers.delete(handler);
    }
  });

  // Utility methods
  async connect(): Promise<string[]> {
    if (!this.state.address) {
      this.state.address = generateMockAddress();
    }
    this.state.isConnected = true;
    this.emit('connect', { chainId: this.state.chainId });
    return [this.state.address];
  }

  async disconnect(): Promise<void> {
    this.state.isConnected = false;
    this.state.address = null;
    this.emit('disconnect');
  }

  async sendTransaction(tx: any): Promise<string> {
    if (!this.state.isConnected) {
      throw new Error('Wallet not connected');
    }

    const txHash = '0x' + Array.from({ length: 64 }, () =>
      Math.floor(Math.random() * 16).toString(16)
    ).join('');

    // Simulate transaction cost
    const value = tx.value ? BigInt(tx.value) : BigInt(0);
    const gasCost = BigInt(100000) * BigInt(1000000000); // gas * gasPrice
    const totalCost = value + gasCost;

    if (this.state.balance < totalCost) {
      throw new Error('Insufficient balance for transaction');
    }

    this.state.balance -= totalCost;

    return txHash;
  }

  async switchChain(chainId: string): Promise<void> {
    this.state.chainId = chainId;
    this.emit('chainChanged', chainId);
  }

  async signMessage(message: string): Promise<string> {
    if (!this.state.isConnected) {
      throw new Error('Wallet not connected');
    }
    return '0x' + 'a'.repeat(130); // Mock signature
  }

  // State management
  setBalance(balance: bigint): void {
    this.state.balance = balance;
  }

  setChainId(chainId: string): void {
    const oldChainId = this.state.chainId;
    this.state.chainId = chainId;
    if (oldChainId !== chainId) {
      this.emit('chainChanged', chainId);
    }
  }

  setAddress(address: string): void {
    const oldAddress = this.state.address;
    this.state.address = address;
    if (oldAddress !== address) {
      this.emit('accountsChanged', [address]);
    }
  }

  getState(): MockWalletState {
    return { ...this.state };
  }

  // Event emitter
  private emit(event: string, data?: any): void {
    const handlers = this.listeners.get(event);
    if (handlers) {
      handlers.forEach((handler) => {
        try {
          handler(data);
        } catch (error) {
          console.error(`Error in ${event} handler:`, error);
        }
      });
    }
  }

  // Simulation methods for testing
  simulateAccountChange(newAddress: string): void {
    this.setAddress(newAddress);
  }

  simulateNetworkChange(chainId: string): void {
    this.setChainId(chainId);
  }

  simulateDisconnect(): void {
    this.disconnect();
  }

  simulateError(method: string, error: Error): void {
    this.request.mockRejectedValueOnce(error);
  }

  // Reset mock
  reset(): void {
    this.state = {
      address: null,
      chainId: '0x128',
      balance: hbarToWei(100),
      isConnected: false,
    };
    this.listeners.clear();
    this.request.mockClear();
    this.on.mockClear();
    this.removeListener.mockClear();
  }
}

// Factory function for creating mock wallet instances
export const createMockWallet = (initialState?: Partial<MockWalletState>): MockWallet => {
  return new MockWallet(initialState);
};

// Global mock wallet for tests
export const setupMockWallet = (initialState?: Partial<MockWalletState>): MockWallet => {
  const mockWallet = createMockWallet(initialState);

  // Replace window.ethereum
  Object.defineProperty(window, 'ethereum', {
    writable: true,
    value: {
      isMetaMask: true,
      request: mockWallet.request,
      on: mockWallet.on,
      removeListener: mockWallet.removeListener,
      selectedAddress: mockWallet.getState().address,
    },
  });

  return mockWallet;
};

// Helper to wait for wallet events
export const waitForWalletEvent = (
  wallet: MockWallet,
  event: string,
  timeout = 5000
): Promise<any> => {
  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(new Error(`Timeout waiting for ${event}`));
    }, timeout);

    const handler = (data: any) => {
      clearTimeout(timeoutId);
      wallet.removeListener(event, handler);
      resolve(data);
    };

    wallet.on(event, handler);
  });
};
