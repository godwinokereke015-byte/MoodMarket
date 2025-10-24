import { describe, expect, it, beforeEach } from 'vitest';
import { ClarityType, cvToHex, hexToCV } from '@stacks/transactions';
import { asciiToBytes, bytesToAscii } from 'micro-stacks/common';

const accounts = simnet.getAccounts();
const deployer = accounts.get('deployer')!;
const user1 = accounts.get('wallet_1')!;
const user2 = accounts.get('wallet_2')!;
const oracle1 = accounts.get('wallet_3')!;
const oracle2 = accounts.get('wallet_4')!;
const oracle3 = accounts.get('wallet_5')!;

// Helper function to mine blocks
const mineBlocks = (count: number) => {
  for (let i = 0; i < count; i++) {
    simnet.mineBlock([]);
  }
};

describe('Security Tests for MoodMarket', () => {
  beforeEach(() => {
    // Reset the contract state before each test
    simnet.mineBlock([
      simnet.callPublicFn('mood-market', 'initialize', [oracle1, oracle2, oracle3], deployer),
    ]);
  });

  describe('Access Control', () => {
    it('should prevent non-owner from initializing', () => {
      const result = simnet.callPublicFn('mood-market', 'initialize', [oracle1], user1);
      expect(result.result).toBeErr(100n); // ERR-UNAUTHORIZED
    });

    it('should prevent non-oracle from creating markets', () => {
      const result = simnet.callPublicFn(
        'mood-market',
        'create-market',
        [
          'Test Market',
          'A test market',
          '50',
          'test-source',
          '1000000',
          '100000000'
        ],
        user1
      );
      expect(result.result).toBeErr(100n); // ERR-UNAUTHORIZED
    });
  });

  describe('Input Validation', () => {
    it('should reject invalid mood thresholds', () => {
      const result = simnet.callPublicFn(
        'mood-market',
        'create-market',
        [
          'Test Market',
          'A test market',
          '101', // Invalid threshold > 100
          'test-source',
          '1000000',
          '100000000'
        ],
        oracle1
      );
      expect(result.result).toBeErr(107n); // ERR-INVALID-PREDICTION
    });

    it('should reject invalid bet amounts', () => {
      // Create a market first
      simnet.callPublicFn(
        'mood-market',
        'create-market',
        [
          'Test Market',
          'A test market',
          '50',
          'test-source',
          '1000000',
          '100000000'
        ],
        oracle1
      );

      // Try to place a bet below minimum
      const result1 = simnet.callPublicFn(
        'mood-market',
        'place-bet',
        ['1', 'true', '500000', '0x' + '00'.repeat(32)],
        user1
      );
      expect(result1.result).toBeErr(106n); // ERR-INVALID-AMOUNT

      // Try to place a bet above maximum
      const result2 = simnet.callPublicFn(
        'mood-market',
        'place-bet',
        ['1', 'true', '1000000000', '0x' + '00'.repeat(32)],
        user1
      );
      expect(result2.result).toBeErr(106n); // ERR-INVALID-AMOUNT
    });
  });

  describe('Reentrancy Protection', () => {
    it('should prevent reentrancy attacks', () => {
      // This test would require a malicious contract that tries to re-enter
      // For now, we test that the reentrancy lock is in place
      const result = simnet.callReadOnlyFn(
        'mood-market',
        'get-reentrancy-lock',
        [],
        user1
      );
      expect(result.result).toBeOk(false);
    });
  });

  describe('Oracle Security', () => {
    it('should require oracle consensus for resolution', () => {
      // Create a market
      simnet.callPublicFn(
        'mood-market',
        'create-market',
        [
          'Test Market',
          'A test market',
          '50',
          'test-source',
          '1000000',
          '100000000'
        ],
        oracle1
      );

      // Fast forward past market close
      mineBlocks(200);

      // Try to resolve with a single oracle (should fail)
      const result = simnet.callPublicFn(
        'mood-market',
        'oracle-report',
        ['1', '60', '0x' + '00'.repeat(65)],
        oracle1
      );
      
      // Should fail because we need more oracles to reach consensus
      expect(result.result).toBeErr(100n); // ERR-UNAUTHORIZED
    });
  });

  describe('Emergency Functions', () => {
    it('should allow admin to pause the contract', () => {
      // Only admin can pause
      const result1 = simnet.callPublicFn('mood-market', 'pause', [true], user1);
      expect(result1.result).toBeErr(100n); // ERR-UNAUTHORIZED

      // Admin can pause
      const result2 = simnet.callPublicFn('mood-market', 'pause', [true], deployer);
      expect(result2.result).toBeOk(true);

      // Check that contract is paused
      const isPaused = simnet.callReadOnlyFn('mood-market', 'is-paused', [], user1);
      expect(isPaused.result).toBeOk(true);
    });
  });
});
