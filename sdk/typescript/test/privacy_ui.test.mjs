import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const htmlPath = path.resolve(__dirname, '../../../website/index.html');
const html = fs.readFileSync(htmlPath, 'utf8');

test('Privacy UI: contains all required DOM elements and action buttons', () => {
  const requiredIds = [
    'privacy-pool',
    'privConnectWalletBtn',
    'privWalletBadge',
    'privPubBal',
    'privPrivBal',
    'privPoolBal',
    'privNotesCount',
    'privMerkleRootDisplay',
    'privShieldAmt',
    'privShieldBtn',
    'privGeneratedBlinding',
    'privGeneratedCommitment',
    'privShieldStatus',
    'privTransferNoteSelect',
    'privTransferRecipient',
    'privTransferBtn',
    'privTransferNullifier',
    'privTransferNewComm',
    'privTransferRoot',
    'privTransferStatus',
    'privUnshieldNoteSelect',
    'privUnshieldRecipient',
    'privUnshieldBtn',
    'privUnshieldNullifier',
    'privUnshieldAmountDisplay',
    'privUnshieldStatus',
    'privFaucetBuyBtn',
    'privVaultRows',
    'privVaultEmpty',
    'privExportNotesBtn',
    'privClearSpentBtn'
  ];

  for (const id of requiredIds) {
    assert.ok(html.includes(`id="${id}"`), `Missing expected DOM id="${id}"`);
  }
});

test('Privacy UI: wires exact Base Sepolia contract addresses and selectors', () => {
  assert.ok(html.includes('0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F'), 'SeraphToken address must be present');
  assert.ok(html.includes('0x06fA7CAfC96Bf988F3d601138976a448e8B99aE6'), 'PrivacyPool address must be present');
  assert.ok(html.includes('0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE'), 'SeraphPresale address must be present');
  assert.ok(html.includes('84532'), 'Base Sepolia chainId must be present');

  // Verify function selectors
  assert.ok(html.includes('0x16479775'), 'approveAndShield selector 0x16479775 must be present');
  assert.ok(html.includes('0x2f9cd91c'), 'privateTransfer selector 0x2f9cd91c must be present');
  assert.ok(html.includes('0x75f658de'), 'unshield selector 0x75f658de must be present');
  assert.ok(html.includes('0xba70f757'), 'getLastRoot selector 0xba70f757 must be present');
  assert.ok(html.includes('0x0be4f422'), 'nextLeafIndex selector 0x0be4f422 must be present');
});
