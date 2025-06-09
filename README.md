# 🗺️ Geogrid - On-Chain Community Maps

> 🌍 Crowdsourced local data stored via smart contract on Stacks blockchain

## 📋 Overview

Geogrid is a decentralized mapping platform that allows communities to collaboratively build and maintain local point-of-interest databases. Users stake STX tokens to add locations, and the community votes to verify accuracy. Verified locations reward their creators, creating incentives for quality contributions.

## ✨ Features

- 📍 **Add Locations**: Submit points of interest with coordinates, categories, and descriptions
- 🗳️ **Community Voting**: Upvote/downvote locations to verify accuracy
- 💰 **Stake & Earn**: Stake STX to add locations, earn rewards when verified
- 🏆 **Reputation System**: Build reputation through quality contributions
- 🗂️ **Categories**: Organized location types (restaurants, shops, parks, etc.)
- 🔍 **Spatial Queries**: Find locations within specific areas

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- STX tokens for staking

### Installation

```bash
git clone <your-repo>
cd geogrid
clarinet console
```

## 📖 Usage

### Initialize Categories (Contract Owner Only)

```clarity
(contract-call? .Geogrid initialize-categories)
```

### Add a New Location

```clarity
(contract-call? .Geogrid add-location 
  40750000    ;; latitude (40.75 * 1000000)
  -73980000   ;; longitude (-73.98 * 1000000)
  "restaurant" 
  "Joe's Pizza" 
  "Best pizza in NYC")
```

### Vote on a Location

```clarity
(contract-call? .Geogrid vote-location u1 "upvote")
```

### Query Location Data

```clarity
(contract-call? .Geogrid get-location u1)
(contract-call? .Geogrid get-locations-in-area 40750000 -73980000 5000000)
```

## 🏗️ Contract Architecture

### 💾 Data Structures

- **Locations**: Core location data with coordinates, metadata, and voting stats
- **User Votes**: Tracks voting history to prevent double-voting
- **User Contributions**: Reputation and contribution tracking
- **Categories**: Approved location categories
- **Coordinate Index**: Spatial indexing for area queries

### 💸 Economics

- **Minimum Stake**: 1 STX (1,000,000 microSTX) required to add locations
- **Verification Threshold**: 3 upvotes needed for verification
- **Reward**: 0.5 STX paid to creators when locations get verified

### 🔐 Security Features

- Coordinate validation (valid lat/lon ranges)
- Category validation against approved list
- Anti-spam: users can't vote on their own locations
- One vote per user per location
- Stake requirement prevents spam submissions

## 🎯 Core Functions

### Public Functions

- `add-location()` - Submit new location with stake
- `vote-location()` - Vote to verify/dispute locations
- `initialize-categories()` - Set up location categories (owner only)
- `add-category()` - Add new location category (owner only)

### Read-Only Functions

- `get-location()` - Retrieve location details
- `get-locations-in-area()` - Spatial query for nearby locations
- `get-user-contributions()` - User stats and reputation
- `get-contract-stats()` - Overall contract metrics

## 🛠️ Development

### Testing

```bash
clarinet test
```

### Deploy

```bash
clarinet deploy --testnet
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🔮 Future Enhancements

- 📱 Mobile app integration
- 🖼️ Image uploads via IPFS
- 🏅 Advanced reputation# Geogrid

