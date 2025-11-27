# 📦 Documentation - Scripts de Sauvegarde VPS

Scripts de sauvegarde et restauration automatiques pour serveur VPS Debian/Ubuntu avec MySQL/MariaDB et Apache.

---

## 📋 Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Prérequis](#prérequis)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Utilisation](#utilisation)
6. [Automatisation (Cron)](#automatisation-cron)
7. [Restauration](#restauration)
8. [Maintenance](#maintenance)
9. [Dépannage](#dépannage)

---

## 🎯 Vue d'ensemble

### Script de sauvegarde (`backup_intranet.sh`)

- **Fonction** : Sauvegarde complète automatique du VPS
- **Contenu sauvegardé** :
  - Toutes les bases de données MySQL/MariaDB utilisateur
  - Répertoire web `/var/www/intranet-inside`
- **Organisation** : Un dossier unique par exécution (`YYYYMMDD_HHMM`)
- **Rotation** : Suppression automatique des sauvegardes > 8 jours
- **Logs** : Fichier `backup.log` dans chaque dossier de sauvegarde

### Script de restauration (`restore.sh`)

- **Fonction** : Restauration complète ou partielle d'une sauvegarde
- **Options** : Restauration totale, uniquement web, ou uniquement bases de données
- **Sécurité** : Sauvegarde temporaire avant restauration, confirmation requise

---

## ⚙️ Prérequis

### Système

- OS : Debian 10+ ou Ubuntu 18.04+
- Accès root ou sudo
- Disque de sauvegarde monté sur `/mnt/backup`

### Logiciels requis

```bash
# Vérifier les dépendances
which mysql mysqldump tar gzip find

# Si manquant, installer :
apt update
apt install mysql-client gzip tar findutils
```

---

## 🚀 Installation

### Étape 1 : Créer le répertoire de scripts

```bash
mkdir -p /mnt/backup/scripts
```

### Étape 2 : Donner les droits d'exécution

```bash
chmod +x /mnt/backup/scripts/backup_intranet.sh
chmod +x /mnt/backup/scripts/restore.sh
```

### Étape 3 : Vérifier les permissions

```bash
ls -lh /mnt/backup/scripts/
```

**Résultat attendu :**
```
-rwxr-xr-x 1 root root 15K Nov 27 14:25 backup_intranet.sh
-rwxr-xr-x 1 root root 12K Nov 27 14:25 restore.sh
```

---

## 🔐 Configuration

### 1. Créer un utilisateur MySQL pour les sauvegardes

```bash
mysql -u root -p
```

```sql
-- Créer l'utilisateur de sauvegarde
CREATE USER 'backupuser'@'localhost' IDENTIFIED BY 'VotreMotDePasseSecurise';

-- Donner les droits de lecture sur toutes les bases
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backupuser'@'localhost';

-- Appliquer les changements
FLUSH PRIVILEGES;

-- Vérifier
SHOW GRANTS FOR 'backupuser'@'localhost';

-- Quitter
EXIT;
```

### 2. Créer le fichier de configuration MySQL

```bash
cat > /root/.my.cnf << 'EOF'
[client]
user=backupuser
password=VotreMotDePasseSecurise
EOF
```

### 3. Sécuriser le fichier de configuration

```bash
chmod 600 /root/.my.cnf
chown root:root /root/.my.cnf
```

### 4. Tester la connexion MySQL

```bash
mysql --defaults-file=/root/.my.cnf -e "SHOW DATABASES;"
```

**Résultat attendu :** Liste des bases de données sans erreur

### 5. Personnaliser les paramètres (optionnel)

Éditer `/mnt/backup/scripts/backup_intranet.sh` et modifier :

```bash
# Nombre de jours de rétention (défaut: 8 jours)
RETENTION_DAYS=8

# Répertoire du site web (défaut: /var/www/intranet-inside)
WEB_ROOT="/var/www/intranet-inside"
```

---

## 💻 Utilisation

### Lancer une sauvegarde manuelle

```bash
/mnt/backup/scripts/backup_intranet.sh
```

### Consulter le log de la dernière sauvegarde

```bash
# Trouver le dernier dossier de sauvegarde
LAST_BACKUP=$(ls -1dt /mnt/backup/2025* | head -n1)

# Afficher le log
cat $LAST_BACKUP/backup.log
```

### Lister toutes les sauvegardes

```bash
ls -lhd /mnt/backup/2025*
```

### Vérifier l'espace disque

```bash
du -sh /mnt/backup
df -h /mnt/backup
```

---

## ⏰ Automatisation (Cron)

### Option 1 : Sauvegardes 3 fois par jour (02h00, 12h00, 18h00)

```bash
# Éditer la crontab root
crontab -e
```

Ajouter les lignes suivantes :

```cron
# Sauvegarde automatique Intranet Inside
0 2 * * * /mnt/backup/scripts/backup_intranet.sh >/dev/null 2>&1
0 12 * * * /mnt/backup/scripts/backup_intranet.sh >/dev/null 2>&1
0 18 * * * /mnt/backup/scripts/backup_intranet.sh >/dev/null 2>&1
```

### Option 2 : Sauvegardes toutes les 6 heures

```cron
# Sauvegarde automatique toutes les 6 heures
0 */6 * * * /mnt/backup/scripts/backup_intranet.sh >/dev/null 2>&1
```

### Option 3 : Sauvegarde quotidienne à 3h00 du matin

```cron
# Sauvegarde quotidienne à 3h00
0 3 * * * /mnt/backup/scripts/backup_intranet.sh >/dev/null 2>&1
```

### Vérifier la crontab

```bash
crontab -l
```

### Tester le cron immédiatement

```bash
# Déclencher manuellement pour tester
/mnt/backup/scripts/backup_intranet.sh
```

---

## 🔄 Restauration

### Restauration complète (site web + bases de données)

```bash
# 1. Lister les sauvegardes disponibles
ls -lhd /mnt/backup/2025*

# 2. Se placer dans le dossier de la sauvegarde à restaurer
cd /mnt/backup/20251127_1425

# 3. Lancer la restauration
/mnt/backup/scripts/restore.sh
```

### Restauration uniquement du site web

```bash
cd /mnt/backup/20251127_1425
/mnt/backup/scripts/restore.sh --web-only
```

### Restauration uniquement des bases de données

```bash
cd /mnt/backup/20251127_1425
/mnt/backup/scripts/restore.sh --db-only
```

### Restauration d'une base de données spécifique

```bash
cd /mnt/backup/20251127_1425

# Lister les bases disponibles
ls -1 *.sql.gz

# Restaurer une base spécifique
gunzip -c ma_base.sql.gz | mysql --defaults-file=/root/.my.cnf ma_base
```

### Vérifier après restauration

```bash
# Tester la configuration Apache
apache2ctl configtest

# Redémarrer Apache
systemctl restart apache2

# Vérifier les bases de données
mysql --defaults-file=/root/.my.cnf -e "SHOW DATABASES;"

# Consulter le log de restauration
ls -lh restore_*.log
cat restore_*.log
```

---

## 🛠️ Maintenance

### Vérifier la taille des sauvegardes

```bash
# Taille totale
du -sh /mnt/backup

# Taille par sauvegarde
du -sh /mnt/backup/2025* | sort -h

# Top 10 des plus grosses sauvegardes
du -sh /mnt/backup/2025* | sort -hr | head -10
```

### Nettoyer manuellement les anciennes sauvegardes

```bash
# Supprimer les sauvegardes de plus de 30 jours
find /mnt/backup -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} \;

# Supprimer une sauvegarde spécifique
rm -rf /mnt/backup/20251101_0200
```

### Sauvegarder les sauvegardes (backup off-site)

```bash
# Synchroniser vers un serveur distant via rsync
rsync -avz --delete /mnt/backup/ user@serveur-distant:/backups/vps/

# Ou via SCP pour une sauvegarde ponctuelle
scp -r /mnt/backup/20251127_1425 user@serveur-distant:/backups/
```

### Tester l'intégrité des sauvegardes

```bash
cd /mnt/backup/20251127_1425

# Tester les archives tar.gz
tar -tzf intranet-inside.tar.gz >/dev/null && echo "OK" || echo "ERREUR"

# Tester les dumps SQL
for f in *.sql.gz; do
    gunzip -t "$f" && echo "$f: OK" || echo "$f: ERREUR"
done
```

---

## 🔍 Dépannage

### Problème : Erreur "Commande non trouvée"

**Cause** : Dépendances manquantes

**Solution** :
```bash
apt update
apt install mysql-client gzip tar findutils coreutils
```

### Problème : Erreur de connexion MySQL

**Cause** : Fichier `/root/.my.cnf` incorrect ou permissions

**Solution** :
```bash
# Vérifier le fichier
cat /root/.my.cnf

# Vérifier les permissions
ls -l /root/.my.cnf
# Doit afficher: -rw------- 1 root root

# Corriger si nécessaire
chmod 600 /root/.my.cnf
chown root:root /root/.my.cnf

# Tester la connexion
mysql --defaults-file=/root/.my.cnf -e "SHOW DATABASES;"
```

### Problème : Disque de sauvegarde plein

**Cause** : Trop de sauvegardes ou rétention trop longue

**Solution** :
```bash
# Vérifier l'espace disque
df -h /mnt/backup

# Réduire la rétention dans le script
# Éditer RETENTION_DAYS dans backup_intranet.sh
nano /mnt/backup/scripts/backup_intranet.sh
# Modifier: RETENTION_DAYS=5  # au lieu de 8

# Nettoyer manuellement
find /mnt/backup -mindepth 1 -maxdepth 1 -type d -mtime +5 -exec rm -rf {} \;
```

### Problème : Permissions incorrectes après restauration web

**Solution** :
```bash
# Corriger les permissions
chown -R www-data:www-data /var/www/intranet-inside
find /var/www/intranet-inside -type d -exec chmod 755 {} \;
find /var/www/intranet-inside -type f -exec chmod 644 {} \;

# Redémarrer Apache
systemctl restart apache2
```

### Problème : Erreur "Cannot create directory"

**Cause** : Permissions insuffisantes sur `/mnt/backup`

**Solution** :
```bash
# Vérifier le montage
df -h /mnt/backup
mount | grep /mnt/backup

# Vérifier les permissions
ls -ld /mnt/backup

# Corriger si nécessaire
chown root:root /mnt/backup
chmod 755 /mnt/backup
```

### Consulter les logs détaillés

```bash
# Log de la dernière sauvegarde
LAST_BACKUP=$(ls -1dt /mnt/backup/2025* | head -n1)
cat $LAST_BACKUP/backup.log

# Rechercher les erreurs
grep -i "erreur" $LAST_BACKUP/backup.log
grep -i "error" $LAST_BACKUP/backup.log

# Logs système
journalctl -u cron | grep backup
tail -f /var/log/syslog | grep backup
```

---

## 📊 Structure d'une sauvegarde

```
/mnt/backup/20251127_1425/
├── backup.log                  # Log de l'exécution
├── intranet-inside.tar.gz      # Archive du site web
├── database1.sql.gz            # Dump de la base 1
├── database2.sql.gz            # Dump de la base 2
└── ...                         # Autres bases
```

---

## 🔒 Sécurité

### Bonnes pratiques

1. **Permissions strictes** :
   ```bash
   chmod 700 /mnt/backup/scripts
   chmod 600 /root/.my.cnf
   ```

2. **Utilisateur MySQL dédié** : N'utilisez jamais `root` MySQL pour les sauvegardes

3. **Sauvegarde off-site** : Copiez régulièrement vers un serveur distant

4. **Chiffrement** (optionnel) :
   ```bash
   # Chiffrer une sauvegarde
   tar -czf - /mnt/backup/20251127_1425 | openssl enc -aes-256-cbc -salt -out backup_encrypted.tar.gz.enc

   # Déchiffrer
   openssl enc -aes-256-cbc -d -in backup_encrypted.tar.gz.enc | tar -xzf -
   ```

5. **Test régulier** : Testez la restauration au moins 1 fois par mois

---

## 📞 Support

Pour plus d'informations, consultez :
- Les logs dans chaque dossier de sauvegarde
- Les commentaires dans les scripts
- La documentation MySQL : https://dev.mysql.com/doc/

---

**Version** : 1.0
**Date** : 2025-11-27
**Auteur** : Script généré pour VPS OVH
