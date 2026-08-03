import "dotenv/config";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  parseEther,
  keccak256,
  stringToHex,
  decodeEventLog,
  type Hex,
  type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Redéploie MandateWithException avec trois gardiens réellement contrôlés, puis
 * exerce le seuil N-sur-M on-chain. Base Sepolia, testnet uniquement.
 *
 * Aucune clé n'est imprimée : seules les adresses apparaissent. Chaque appel est
 * encadré et son issue rapportée telle quelle.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const artifact = JSON.parse(readFileSync(resolve(root, "build/MandateWithException.json"), "utf8"));
const abi = artifact.abi;

const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });

const deployer = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const wallet = createWalletClient({ account: deployer, chain: baseSepolia, transport: http(rpcUrl) });

const guardians = [1, 2, 3].map((i) => privateKeyToAccount(process.env[`GUARDIAN${i}_KEY`] as Hex));
const gWallets = guardians.map((a) =>
  createWalletClient({ account: a, chain: baseSepolia, transport: http(rpcUrl) })
);

let CONTRACT: Address;
const out: any = { network: "base-sepolia", chainId: 84532, steps: [] };
const log = (...a: any[]) => console.log(...a);

async function waitVisible(check: () => Promise<boolean>, tries = 30) {
  for (let i = 0; i < tries; i++) {
    try {
      if (await check()) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error("état jamais visible côté RPC");
}

/** Envoie et rapporte l'issue brute, sans la qualifier. */
async function attempt(label: string, w: any, fn: string, args: any[]) {
  let simulation = "";
  try {
    await pub.simulateContract({ address: CONTRACT, abi, functionName: fn, args, account: w.account });
    simulation = "aboutit";
  } catch (e: any) {
    simulation = e.shortMessage ?? String(e).split("\n")[0];
  }

  let tx = "";
  let status = "";
  try {
    tx = await w.writeContract({ address: CONTRACT, abi, functionName: fn, args, gas: 400_000n });
    const r = await pub.waitForTransactionReceipt({ hash: tx as Hex });
    status = r.status;
  } catch (e: any) {
    status = "non diffusée";
  }
  log(`   ${label}`);
  log(`        simulation : ${simulation.split("\n").join(" ")}`);
  if (tx) log(`        tx ${tx} → ${status}`);
  else log(`        (aucune tx)`);
  out.steps.push({ label, fn, simulation, tx, status });
  return { tx, status };
}

log("déployeur :", deployer.address);
log("solde     :", formatEther(await pub.getBalance({ address: deployer.address })), "ETH");
guardians.forEach((g, i) => log(`gardien ${i + 1}  : ${g.address}`));

// ---------- filet de gaz pour les gardiens ----------
log("\n── financement des gardiens (filet de gaz) ──");
for (let i = 0; i < 3; i++) {
  const g = guardians[i]!;
  const bal = await pub.getBalance({ address: g.address });
  if (bal >= parseEther("0.0005")) {
    log(`   gardien ${i + 1} : déjà ${formatEther(bal)} ETH, pas de virement`);
    continue;
  }
  const h = await wallet.sendTransaction({ to: g.address, value: parseEther("0.002") });
  await pub.waitForTransactionReceipt({ hash: h });
  log(`   gardien ${i + 1} : 0.002 ETH · tx ${h}`);
  out.steps.push({ label: `financement gardien ${i + 1}`, tx: h });
}

// ---------- déploiement ----------
log("\n── déploiement de MandateWithException, 3 gardiens contrôlés ──");
const depHash = await wallet.deployContract({
  abi,
  bytecode: artifact.bytecode as Hex,
  args: [guardians.map((g) => g.address), parseEther("0.5"), parseEther("0.2"), 2n],
});
const depR = await pub.waitForTransactionReceipt({ hash: depHash });
if (depR.status !== "success" || !depR.contractAddress) throw new Error("déploiement échoué");
CONTRACT = depR.contractAddress as Address;
log("   adresse :", CONTRACT);
log("   tx      :", depHash, "→", depR.status, "· gaz", depR.gasUsed);
out.contract = CONTRACT;
out.deployTx = depHash;
out.deployBlock = depR.blockNumber.toString();

await waitVisible(async () => {
  const c = await pub.getCode({ address: CONTRACT });
  return !!c && c !== "0x";
});

const read = async (fn: string, args: any[] = []) =>
  pub.readContract({ address: CONTRACT, abi, functionName: fn, args });

log("   guardianCount()            :", await read("guardianCount"));
for (let i = 0; i < 3; i++) {
  log(`   isGuardian(gardien ${i + 1})       :`, await read("isGuardian", [guardians[i]!.address]));
}
log("   isGuardian(déployeur)      :", await read("isGuardian", [deployer.address]));

// ---------- budget ----------
log("\n── création du budget (agent = déployeur, distinct des gardiens) ──");
const CAP = parseEther("1");
const bHash = await wallet.writeContract({
  address: CONTRACT,
  abi,
  functionName: "createBudget",
  args: [deployer.address, CAP],
});
const bR = await pub.waitForTransactionReceipt({ hash: bHash });
let budgetId = 0n;
for (const l of bR.logs) {
  try {
    const d: any = decodeEventLog({ abi, data: l.data, topics: l.topics });
    if (d.eventName === "BudgetCreated") budgetId = d.args.id;
  } catch {}
}
log("   budgetId :", budgetId.toString(), "· cap 1 ETH · tx", bHash);
out.budgetId = budgetId.toString();

await waitVisible(async () => {
  const b: any = await read("budgetOf", [budgetId]);
  return b[0].toLowerCase() === deployer.address.toLowerCase();
});

// consommer presque tout le plafond
const dHash = await wallet.writeContract({
  address: CONTRACT,
  abi,
  functionName: "draw",
  args: [budgetId, keccak256(stringToHex("ops")), parseEther("0.9")],
});
await pub.waitForTransactionReceipt({ hash: dHash });
log("   draw(0.9 ETH) · tx", dHash);

// ---------- la grosse exception ----------
const CAT = keccak256(stringToHex("ops"));
const BIG = parseEther("0.3"); // > bigThreshold 0.2
log("\n── grosse exception : 0.3 ETH, au-dessus du seuil de 0.2 ──");
log("   requiredApprovals(0.3 ETH) :", await read("requiredApprovals", [BIG]));

const expiry = BigInt(Math.floor(Date.now() / 1000) + 7 * 24 * 3600);
const BET = keccak256(stringToHex("le paiement debloque la livraison sous 48h"));
const READ = keccak256(stringToHex("lecture neutre datee avant le resultat"));

log("\n   1) le gardien 1 propose");
const pHash = await gWallets[0]!.writeContract({
  address: CONTRACT,
  abi,
  functionName: "proposeException",
  args: [budgetId, CAT, BIG, expiry, BET, READ],
});
const pR = await pub.waitForTransactionReceipt({ hash: pHash });
let excId = 0n;
for (const l of pR.logs) {
  try {
    const d: any = decodeEventLog({ abi, data: l.data, topics: l.topics });
    if (d.eventName === "ExceptionProposed") excId = d.args.exceptionId;
  } catch {}
}
log(`        exceptionId ${excId} · tx ${pHash} → ${pR.status}`);
out.exceptionId = excId.toString();
out.proposeTx = pHash;

await waitVisible(async () => {
  const e: any = await read("exceptionOf", [excId]);
  return e[7] === 1n;
});
log("        approbateurs :", (await read("exceptionOf", [excId]) as any)[7]);

log("\n   2) tirage avec UN seul approbateur");
await attempt("drawWithException(0.05) — 1 approbateur", wallet, "drawWithException", [
  budgetId,
  excId,
  CAT,
  parseEther("0.05"),
]);

log("\n   3) le gardien 1 tente d'approuver une seconde fois");
await attempt("approveException — même gardien", gWallets[0]!, "approveException", [excId]);

log("\n   4) le gardien 2 approuve");
const a2 = await attempt("approveException — gardien 2", gWallets[1]!, "approveException", [excId]);
if (a2.status === "success") {
  await waitVisible(async () => {
    const e: any = await read("exceptionOf", [excId]);
    return e[7] === 2n;
  });
}
log("        approbateurs :", (await read("exceptionOf", [excId]) as any)[7]);

log("\n   5) tirage avec DEUX approbateurs");
await attempt("drawWithException(0.05) — 2 approbateurs", wallet, "drawWithException", [
  budgetId,
  excId,
  CAT,
  parseEther("0.05"),
]);

// ---------- lectures finales ----------
log("\n── lectures de contrôle ──");
const e: any = await read("exceptionOf", [excId]);
log("   montant accordé   :", formatEther(e[2]), "ETH");
log("   consommée         :", e[6]);
log("   approbateurs      :", e[7].toString());
const apps: any = await read("approversOf", [excId]);
apps.forEach((a: string, i: number) => log(`   approbateur ${i}     : ${a}`));
const b: any = await read("budgetOf", [budgetId]);
log("   spent             :", formatEther(b[3]), "ETH");
log("   exceptionAllowance:", formatEther(b[4]), "ETH");
log("   plafond effectif  :", formatEther((await read("effectiveCeiling", [budgetId])) as bigint), "ETH");

log("\nsolde restant :", formatEther(await pub.getBalance({ address: deployer.address })), "ETH");
writeFileSync(resolve(root, "build/exception-live.json"), JSON.stringify(out, null, 2));
log("→ build/exception-live.json");
