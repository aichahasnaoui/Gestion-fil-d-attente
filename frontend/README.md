# 🏥 Projet PFA : Plateforme Digitale de Gestion de Santé et Files d'Attente

Cette application Flutter est le cœur d'une solution complète de numérisation visant à optimiser la prise de rendez-vous médicaux et la gestion des flux dans les établissements de services (cliniques, banques, administrations).

## 🚀 Fonctionnalités Clés

### 👥 Gestion Multi-Rôles
- **Patient / Client** : Recherche de services, prise de rendez-vous intelligente, et obtention de tickets virtuels.
- **Médecin** : Gestion d'agenda, validation de rendez-vous et suivi des dossiers patients.
- **Admin Service** : Contrôle des guichets, appel des tickets et statistiques de flux en temps réel.

### 🛠️ Caractéristiques Techniques
- **Temps Réel (Socket.io)** : Mises à jour instantanées de la file d'attente et notifications push pour les utilisateurs.
- **Moteur de Rendez-vous** : Détection automatique des conflits d'horaires basée sur la durée de consultation personnalisée de chaque médecin.
- **Smart Ticketing** : Système de file d'attente virtuel avec calcul du temps d'attente estimé.
- **Sécurité** : Authentification robuste par JWT, stockage sécurisé des tokens et récupération de compte par OTP.

## 💻 Stack Technique

- **Frontend** : [Flutter](https://flutter.dev) (Dart)
- **Backend** : Flask (Python) avec SQLAlchemy
- **Communication** : API REST (Dio) & WebSockets (Socket.io)
- **Gestion d'état** : Provider / SetState

## 🏁 Démarrage Rapide

### Prérequis
- Flutter SDK (dernière version stable)
- Backend Flask configuré et en cours d'exécution

### Installation

1. **Installation des dépendances** :
   ```bash
   flutter pub get
   ```

2. **Configuration de l'API** :
   Modifiez `lib/constants.dart` pour renseigner l'URL de votre serveur backend.

3. **Lancement de l'application** :
   ```bash
   flutter run
   ```
