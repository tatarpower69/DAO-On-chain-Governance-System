const TOKEN_ADDRESS = "0x2d16DA4Df8CFB3A6962Aa28Dce9d0c6F089d6ac7";
const BOX_ADDRESS = "0xf5E073F7BCf6C4D7919cA1975B2c0e7B439E9379";
const GOVERNOR_ADDRESS = "0x3677a451d2D2DC332CF45c5EDd09144f8C8E06d4";

const TOKEN_ABI = [
    "function balanceOf(address) view returns (uint256)",
    "function getVotes(address) view returns (uint256)",
    "function delegates(address) view returns (address)",
    "function delegate(address)"
];

const GOVERNOR_ABI = [
    "function castVote(uint256, uint8) returns (uint256)",
    "function state(uint256) view returns (uint8)",
    "function propose(address[], uint256[], bytes[], string) returns (uint256)",
    "function hasVoted(uint256, address) view returns (bool)",
    "function proposalVotes(uint256) view returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)",
    "event ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 voteStart, uint256 voteEnd, string description)"
];

const STATE_NAMES = ["Pending", "Active", "Canceled", "Defeated", "Succeeded", "Queued", "Expired", "Executed"];
const STATE_CLASSES = ["pending", "active", "default", "defeated", "succeeded", "default", "default", "succeeded"];

let provider, signer, account;
let busy = false;

function showStatus(msg) {
    const bar = document.getElementById("status-bar");
    document.getElementById("status-text").textContent = msg;
    bar.classList.remove("hidden");
    setTimeout(() => bar.classList.add("hidden"), 4000);
}

document.getElementById("connect-wallet").addEventListener("click", async () => {
    if (!window.ethereum) return alert("Install MetaMask first");
    provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    signer = await provider.getSigner();
    account = await signer.getAddress();

    document.getElementById("wallet-address").textContent = "Address: " + account;
    document.getElementById("stats-section").classList.remove("hidden");
    document.getElementById("create-proposal-section").classList.remove("hidden");
    document.getElementById("proposals-section").classList.remove("hidden");

    await refreshStats();
    await refreshProposals();
});

document.getElementById("delegate-btn").addEventListener("click", async () => {
    if (busy) return;
    const addr = document.getElementById("delegate-address").value.trim();
    if (!addr) return alert("Enter an address to delegate to");
    busy = true;
    showStatus("⏳ Delegating votes...");
    try {
        const token = new ethers.Contract(TOKEN_ADDRESS, TOKEN_ABI, signer);
        const tx = await token.delegate(addr);
        showStatus("⏳ Waiting for confirmation...");
        await tx.wait();
        showStatus("✅ Delegation successful!");
        await refreshStats();
    } catch (e) {
        if (e.code === "ACTION_REJECTED") { showStatus("❌ Transaction cancelled"); }
        else { console.error(e); showStatus("❌ Delegation failed"); }
    }
    busy = false;
});

document.getElementById("propose-btn").addEventListener("click", async () => {
    if (busy) return;
    const val = document.getElementById("proposal-value").value;
    if (!val) return alert("Enter a value");
    busy = true;
    showStatus("⏳ Creating proposal...");
    try {
        const gov = new ethers.Contract(GOVERNOR_ADDRESS, GOVERNOR_ABI, signer);
        const iface = new ethers.Interface(["function store(uint256)"]);
        const calldata = iface.encodeFunctionData("store", [val]);
        const tx = await gov.propose([BOX_ADDRESS], [0], [calldata], "Proposal: Store " + val + " in Box");
        showStatus("⏳ Waiting for confirmation...");
        await tx.wait();
        showStatus("✅ Proposal created! Refresh to see it.");
        document.getElementById("proposal-value").value = "";
        await refreshProposals();
    } catch (e) {
        if (e.code === "ACTION_REJECTED") { showStatus("❌ Transaction cancelled"); }
        else { console.error(e); showStatus("❌ Error creating proposal"); }
    }
    busy = false;
});

document.getElementById("refresh-btn").addEventListener("click", () => {
    refreshProposals();
});

async function refreshStats() {
    try {
        const token = new ethers.Contract(TOKEN_ADDRESS, TOKEN_ABI, provider);
        const [balance, votes, delegate] = await Promise.all([
            token.balanceOf(account),
            token.getVotes(account),
            token.delegates(account)
        ]);
        document.getElementById("token-balance").textContent = parseFloat(ethers.formatEther(balance)).toLocaleString();
        document.getElementById("voting-power").textContent = parseFloat(ethers.formatEther(votes)).toLocaleString();
        document.getElementById("delegated-to").textContent = delegate === ethers.ZeroAddress ? "None" : delegate;
    } catch (e) {
        console.error("Stats error:", e);
    }
}

async function refreshProposals() {
    const list = document.getElementById("proposals-list");
    list.innerHTML = '<p style="color:var(--text-muted)">Loading proposals...</p>';

    try {
        const gov = new ethers.Contract(GOVERNOR_ADDRESS, GOVERNOR_ABI, provider);
        const events = await gov.queryFilter(gov.filters.ProposalCreated(), -200000);

        if (events.length === 0) {
            list.innerHTML = '<p style="color:var(--text-muted)">No proposals found. Create one above!</p>';
            return;
        }

        list.innerHTML = "";

        for (let i = events.length - 1; i >= 0; i--) {
            const ev = events[i];
            const proposalId = ev.args.proposalId;
            const description = ev.args.description;
            const stateNum = Number(await gov.state(proposalId));
            const voted = await gov.hasVoted(proposalId, account);

            let forVotes = 0n, againstVotes = 0n, abstainVotes = 0n;
            try {
                const votes = await gov.proposalVotes(proposalId);
                againstVotes = votes[0];
                forVotes = votes[1];
                abstainVotes = votes[2];
            } catch (e) {  }

            const card = document.createElement("div");
            card.className = "proposal-card";

            const idEl = document.createElement("p");
            idEl.className = "proposal-id";
            idEl.textContent = "ID: " + proposalId.toString().substring(0, 16) + "...";
            card.appendChild(idEl);

            const descEl = document.createElement("p");
            descEl.className = "proposal-desc";
            descEl.textContent = description;
            card.appendChild(descEl);

            const statusEl = document.createElement("p");
            const badge = document.createElement("span");
            badge.className = "badge badge-" + STATE_CLASSES[stateNum];
            badge.textContent = STATE_NAMES[stateNum];
            statusEl.appendChild(badge);

            if (voted) {
                const votedBadge = document.createElement("span");
                votedBadge.className = "badge badge-voted";
                votedBadge.textContent = "✓ You Voted";
                votedBadge.style.marginLeft = "0.4rem";
                statusEl.appendChild(votedBadge);
            }
            card.appendChild(statusEl);

            const resultsEl = document.createElement("div");
            resultsEl.className = "vote-results";
            resultsEl.innerHTML =
                '<span>For: <span class="for-count">' + formatVotes(forVotes) + '</span></span>' +
                '<span>Against: <span class="against-count">' + formatVotes(againstVotes) + '</span></span>' +
                '<span>Abstain: <span class="abstain-count">' + formatVotes(abstainVotes) + '</span></span>';
            card.appendChild(resultsEl);

            const isActive = stateNum === 1;
            const btnsDiv = document.createElement("div");
            btnsDiv.className = "vote-btns";

            if (isActive && !voted) {
                createVoteButton(btnsDiv, "For", "vote-for", proposalId, 1, gov);
                createVoteButton(btnsDiv, "Against", "vote-against", proposalId, 0, gov);
                createVoteButton(btnsDiv, "Abstain", "vote-abstain", proposalId, 2, gov);
            } else if (voted) {
                const info = document.createElement("p");
                info.style.cssText = "font-size:0.8rem; color:var(--success); margin-top:0.25rem;";
                info.textContent = "✓ Your vote has been recorded on-chain";
                btnsDiv.appendChild(info);
            } else {
                const info = document.createElement("p");
                info.style.cssText = "font-size:0.8rem; color:var(--text-muted); margin-top:0.25rem;";
                info.textContent = "Voting not available (status: " + STATE_NAMES[stateNum] + ")";
                btnsDiv.appendChild(info);
            }

            card.appendChild(btnsDiv);
            list.appendChild(card);
        }
    } catch (e) {
        console.error("Load error:", e);
        list.innerHTML = '<p style="color:var(--danger)">Error loading proposals</p>';
    }
}

function formatVotes(v) {
    const n = parseFloat(ethers.formatEther(v));
    if (n === 0) return "0";
    return n.toLocaleString();
}

function createVoteButton(container, label, cssClass, proposalId, support, gov) {
    const btn = document.createElement("button");
    btn.textContent = label;
    btn.className = "vote-btn " + cssClass;

    btn.addEventListener("click", async () => {
        if (busy) return;
        busy = true;
        btn.disabled = true;
        btn.textContent = label + "...";
        showStatus("⏳ Casting vote: " + label + "...");

        try {
            const govSigner = gov.connect(signer);
            const tx = await govSigner.castVote(proposalId, support);
            showStatus("⏳ Waiting for confirmation...");
            await tx.wait();
            showStatus("✅ Vote cast successfully! (" + label + ")");
            await refreshProposals();
        } catch (e) {
            btn.disabled = false;
            btn.textContent = label;
            if (e.code === "ACTION_REJECTED") {
                showStatus("❌ Transaction cancelled");
            } else if (e.message && e.message.includes("AlreadyCastVote")) {
                showStatus("⚠️ You already voted on this proposal");
                await refreshProposals();
            } else {
                console.error("Vote error:", e);
                showStatus("❌ Vote failed — see console");
            }
        }
        busy = false;
    });

    container.appendChild(btn);
}
