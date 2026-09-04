# AI-SES: AI-Powered Smart Escrow System

> Proactive Cryptocurrency Fraud Prevention on Ethereum Blockchain

**Student:** Saniya Machhaliya
**Supervisor:** Dr. John Ayoade
**Unit:** NIT6002 IT Research Project 2
**University:** Victoria University, Melbourne
**Year:** 2026

---

## Overview

AI-SES is a proactive fraud prevention system that stops cryptocurrency fraud **before** a transaction executes — not after the money is already gone.

The system intercepts a transaction at the MetaMask wallet stage, runs it through a trained Random Forest classifier to generate a fraud risk score (0–100), and passes that score to a Solidity smart contract deployed on Ethereum. The contract then automatically releases, holds, or rejects the funds based on the score — all in under 500 milliseconds.

---

## The Research Gap

Every existing fraud detection system in the literature — Weber et al. (2019), EvolveGCN (2020) — runs **post-hoc**. They detect fraud after the transaction has already executed. Since blockchain transactions are irreversible, detection after the fact is too late.

AI-SES is the first system to combine:
- Real-time ML risk scoring
- Blockchain-enforced pre-execution prevention
- Automated escrow decision logic

---

## System Architecture

```
User (MetaMask)
      ↓
Transaction Intercepted  ← Stage 3: before blockchain
      ↓
Feature Extraction (166 features)
      ↓
Random Forest Classifier → Risk Score (0–100)
      ↓
AISmartEscrow.sol
      ↓
Score < 30  → LOW    → Funds released immediately
Score 30–70 → MEDIUM → Funds held in escrow (24h review)
Score > 70  → HIGH   → Transaction rejected, funds refunded
```

---

## Results

Evaluated on the Elliptic Bitcoin Dataset (same benchmark as Weber et al.):

| Model | F1-Score | AUC-ROC | FPR |
|---|---|---|---|
| Logistic Regression | 0.714 | 0.891 | 0.083 |
| Decision Tree | 0.890 | 0.931 | 0.074 |
| GBT — Weber et al. (2019) | 0.947 | 0.997 | 0.038 |
| MLP Neural Network | 0.819 | 0.968 | 0.049 |
| EvolveGCN | 0.931 | 0.978 | 0.031 |
| **Random Forest (AI-SES)** | **0.939** | **0.996** | **0.028** |

---

## Dataset

**Elliptic Bitcoin Dataset** (Weber et al., 2019 / MIT & Elliptic Inc.)

- 203,769 total Bitcoin transactions
- 46,564 labeled (42,019 licit, 4,545 illicit)
- 166 features per transaction
- Class imbalance fixed using SMOTE (Chawla et al., 2002)
  - Fraud examples: 3,284 → 10,018 (3.1× increase)

---

## Smart Contract Deployment

| Detail | Value |
|---|---|
| Network | Ethereum Sepolia Testnet |
| Contract Address | `0x6691567b75c6A30A7240C4434106F3e91A16f786` |
| Verify on Etherscan | [sepolia.etherscan.io](https://sepolia.etherscan.io/address/0x6691567b75c6A30A7240C4434106F3e91A16f786) |
| Transactions | 3 confirmed `depositFunds` calls |
| Block Confirmations | 6,287+ |

---

## Repository Structure

```
AI-SES-Project/
├── notebooks/
│   ├── ai_ses_final.ipynb           # ML model training (Elliptic dataset)
│   └── ai_ses_connect_pro.ipynb     # Web3 integration + blockchain tests
├── contract/
│   └── AISmartEscrow.sol            # Solidity smart contract
├── presentation/
│   └── AI_SES_Presentation.pptx    # Final presentation slides
└── README.md
```

---

## How to Run

### 1. ML Model (Google Colab)

```python
# Open ai_ses_final.ipynb in Google Colab
# Upload the Elliptic dataset to Google Drive at:
# /content/drive/MyDrive/Colab Notebooks/Final Year Project/

# Run all cells — model trains and saves:
# rf_model.pkl
# scaler.pkl
```

### 2. Smart Contract (Remix IDE)

```
1. Open https://remix.ethereum.org
2. Upload AISmartEscrow.sol
3. Compile with Solidity ^0.8.19
4. Connect MetaMask to Sepolia Testnet
5. Deploy with your wallet address as _reviewer
```

### 3. Web3 Integration (Google Colab)

```python
# Open ai_ses_connect_pro.ipynb in Google Colab
# Update PRIVATE_KEY with your MetaMask private key
# Run all cells — executes 3 end-to-end test transactions
```

---

## Key Technical Components

| Component | Details |
|---|---|
| ML Model | Random Forest, 500 trees, max_depth=20 |
| Balancing | SMOTE (Chawla et al., 2002) |
| Normalisation | RobustScaler (fit on train only) |
| Smart Contract | Solidity ^0.8.19, ReentrancyGuard |
| Security Pattern | Checks-Effects-Interactions |
| Oracle | ecrecover signature verification |
| Blockchain | Ethereum Sepolia Testnet |
| Web3 Library | Web3.py |

---

## References

1. Weber, M. et al. (2019). Anti-money laundering in bitcoin. *arXiv:1908.02591*
2. Breiman, L. (2001). Random forests. *Machine Learning, 45(1), 5–32*
3. Chawla, N. V. et al. (2002). SMOTE. *JAIR, 16, 321–357*
4. Pareja, A. et al. (2020). EvolveGCN. *AAAI 2020*
5. Akoglu, L. et al. (2015). Graph-based anomaly detection. *DMKD, 29(3)*
6. Luu, L. et al. (2016). Making smart contracts smarter. *ACM CCS*
7. Atzei, N. et al. (2017). Survey of attacks on Ethereum. *POST 2017*
8. Wohrer, M. & Zdun, U. (2018). Smart contract security patterns. *WICSA*
9. Chainalysis. (2023). The 2023 Crypto Crime Report

---

## License

This project was submitted as academic coursework at Victoria University.
For research and educational use only.
