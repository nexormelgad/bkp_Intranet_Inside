#!/bin/bash
################################################################################
# Script de restauration pour VPS Debian/Ubuntu
#
# Fonctionnement :
# - À lancer depuis le répertoire de sauvegarde à restaurer
# - Restaure les bases de données MySQL
# - Restaure le répertoire du site web
# - Génère un log de la restauration
#
# Utilisation :
#   cd /mnt/backup/YYYYMMDD_HHMM
#   /mnt/backup/scripts/restore.sh
#
# Options :
#   /mnt/backup/scripts/restore.sh --web-only     # Restaurer uniquement le site web
#   /mnt/backup/scripts/restore.sh --db-only      # Restaurer uniquement les bases de données
#   /mnt/backup/scripts/restore.sh --all          # Restaurer tout (par défaut)
#
# Prérequis :
#   - Fichier /root/.my.cnf avec les credentials MySQL
#   - Droits root ou sudo
#
# Auteur : Script généré pour restauration VPS OVH
# Date : 2025-11-27
################################################################################

set -o pipefail

#==============================================================================
# CONFIGURATION - Modifier selon vos besoins
#==============================================================================

# Répertoire du site web (destination de la restauration)
WEB_ROOT="/var/www/intranet-inside"

# Fichier de configuration MySQL
MYSQL_CNF="/root/.my.cnf"

#==============================================================================
# VARIABLES INTERNES
#==============================================================================

# Répertoire de sauvegarde (répertoire courant)
BACKUP_DIR=$(pwd)

# Fichier de log de restauration
RESTORE_LOG="$BACKUP_DIR/restore_$(date +'%Y%m%d_%H%M%S').log"

# Chemins des commandes
MYSQL="/usr/bin/mysql"
TAR="/bin/tar"
GUNZIP="/bin/gunzip"

# Options de restauration
RESTORE_WEB=1
RESTORE_DB=1

# Compteurs
TOTAL_ERRORS=0
DATABASES_RESTORED=0
DATABASES_FAILED=0

#==============================================================================
# FONCTIONS UTILITAIRES
#==============================================================================

# Fonction d'affichage avec timestamp
log_message() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$RESTORE_LOG"
}

# Fonction de vérification de commande
check_command() {
    local cmd="$1"
    if [ ! -x "$cmd" ]; then
        log_message "ERREUR" "Commande non trouvée ou non exécutable: $cmd"
        return 1
    fi
    return 0
}

# Fonction d'affichage de l'aide
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --all         Restaurer tout (site web + bases de données) [par défaut]
  --web-only    Restaurer uniquement le site web
  --db-only     Restaurer uniquement les bases de données
  -h, --help    Afficher cette aide

Instructions:
  1. Se placer dans le répertoire de sauvegarde à restaurer
  2. Lancer le script: $0

Exemple:
  cd /mnt/backup/20251127_1425
  /mnt/backup/scripts/restore.sh

EOF
}

# Fonction de confirmation
confirm() {
    local message="$1"
    local response

    echo ""
    echo "⚠️  $message"
    read -p "Voulez-vous continuer? (oui/non): " response

    case "$response" in
        oui|OUI|yes|YES|y|Y)
            return 0
            ;;
        *)
            log_message "INFO" "Opération annulée par l'utilisateur"
            return 1
            ;;
    esac
}

#==============================================================================
# ANALYSE DES ARGUMENTS
#==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            RESTORE_WEB=1
            RESTORE_DB=1
            shift
            ;;
        --web-only)
            RESTORE_WEB=1
            RESTORE_DB=0
            shift
            ;;
        --db-only)
            RESTORE_WEB=0
            RESTORE_DB=1
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Option inconnue: $1"
            show_usage
            exit 1
            ;;
    esac
done

#==============================================================================
# INITIALISATION
#==============================================================================

log_message "INFO" "=========================================="
log_message "INFO" "Début de la restauration"
log_message "INFO" "=========================================="
log_message "INFO" "Répertoire de sauvegarde: $BACKUP_DIR"
log_message "INFO" "Fichier de log: $RESTORE_LOG"

# Vérifier qu'on est dans un répertoire de sauvegarde valide
if [ ! -f "$BACKUP_DIR/backup.log" ]; then
    log_message "AVERTISSEMENT" "Le fichier backup.log n'a pas été trouvé dans ce répertoire"
    log_message "AVERTISSEMENT" "Assurez-vous d'être dans le bon répertoire de sauvegarde"
fi

#==============================================================================
# VÉRIFICATIONS PRÉALABLES
#==============================================================================

log_message "INFO" "Vérification des prérequis..."

# Vérifier les droits root
if [ "$(id -u)" -ne 0 ]; then
    log_message "ERREUR" "Ce script doit être exécuté en tant que root ou avec sudo"
    exit 1
fi

# Vérifier les commandes nécessaires
MISSING_COMMANDS=0
for cmd in "$MYSQL" "$TAR" "$GUNZIP"; do
    if ! check_command "$cmd"; then
        MISSING_COMMANDS=$((MISSING_COMMANDS + 1))
    fi
done

if [ $MISSING_COMMANDS -gt 0 ]; then
    log_message "ERREUR" "$MISSING_COMMANDS commande(s) manquante(s)"
    exit 1
fi

# Vérifier le fichier de configuration MySQL si restauration DB
if [ $RESTORE_DB -eq 1 ]; then
    if [ ! -f "$MYSQL_CNF" ]; then
        log_message "ERREUR" "Fichier de configuration MySQL non trouvé: $MYSQL_CNF"
        exit 1
    fi
fi

log_message "OK" "Vérifications préalables terminées"

#==============================================================================
# AFFICHAGE DU CONTENU DE LA SAUVEGARDE
#==============================================================================

log_message "INFO" "Contenu de la sauvegarde:"
log_message "INFO" ""

# Lister les fichiers SQL
SQL_FILES=$(ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null)
SQL_COUNT=$(echo "$SQL_FILES" | grep -c ".sql.gz" 2>/dev/null || echo "0")

if [ "$SQL_COUNT" -gt 0 ]; then
    log_message "INFO" "Bases de données trouvées: $SQL_COUNT"
    for sql_file in $SQL_FILES; do
        db_name=$(basename "$sql_file" .sql.gz)
        file_size=$(du -h "$sql_file" | cut -f1)
        log_message "INFO" "  - $db_name ($file_size)"
    done
else
    log_message "INFO" "Aucune base de données trouvée"
fi

log_message "INFO" ""

# Vérifier l'archive web
if [ -f "$BACKUP_DIR/intranet-inside.tar.gz" ]; then
    archive_size=$(du -h "$BACKUP_DIR/intranet-inside.tar.gz" | cut -f1)
    log_message "INFO" "Site web trouvé: intranet-inside.tar.gz ($archive_size)"
else
    log_message "INFO" "Aucune archive du site web trouvée"
fi

log_message "INFO" ""

#==============================================================================
# CONFIRMATION DE LA RESTAURATION
#==============================================================================

echo ""
echo "=========================================="
echo "RESTAURATION À EFFECTUER"
echo "=========================================="

if [ $RESTORE_DB -eq 1 ] && [ "$SQL_COUNT" -gt 0 ]; then
    echo "✓ Bases de données: $SQL_COUNT base(s) seront restaurées"
fi

if [ $RESTORE_WEB -eq 1 ] && [ -f "$BACKUP_DIR/intranet-inside.tar.gz" ]; then
    echo "✓ Site web: sera restauré dans $WEB_ROOT"
fi

echo ""

# Demander confirmation
if ! confirm "ATTENTION: Cette opération va ÉCRASER les données existantes!"; then
    log_message "INFO" "Restauration annulée"
    exit 0
fi

#==============================================================================
# RESTAURATION DES BASES DE DONNÉES
#==============================================================================

if [ $RESTORE_DB -eq 1 ]; then
    log_message "INFO" "------------------------------------------"
    log_message "INFO" "RESTAURATION DES BASES DE DONNÉES"
    log_message "INFO" "------------------------------------------"

    if [ "$SQL_COUNT" -eq 0 ]; then
        log_message "INFO" "Aucune base de données à restaurer"
    else
        for sql_file in $SQL_FILES; do
            db_name=$(basename "$sql_file" .sql.gz)
            log_message "INFO" "Restauration de la base: $db_name"

            # Vérifier si la base existe
            DB_EXISTS=$($MYSQL --defaults-file="$MYSQL_CNF" -N -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$db_name';" 2>/dev/null)

            if [ -n "$DB_EXISTS" ]; then
                log_message "INFO" "La base $db_name existe déjà, suppression pour restauration complète..."
                $MYSQL --defaults-file="$MYSQL_CNF" -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>&1 >> "$RESTORE_LOG"

                if [ $? -ne 0 ]; then
                    log_message "ERREUR" "Impossible de supprimer la base: $db_name"
                    DATABASES_FAILED=$((DATABASES_FAILED + 1))
                    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
                    continue
                fi
            fi

            # Créer la base
            log_message "INFO" "Création de la base $db_name..."
            $MYSQL --defaults-file="$MYSQL_CNF" -e "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1 >> "$RESTORE_LOG"

            if [ $? -ne 0 ]; then
                log_message "ERREUR" "Impossible de créer la base: $db_name"
                DATABASES_FAILED=$((DATABASES_FAILED + 1))
                TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
                continue
            fi

            # Restaurer la base (décompression + import)
            log_message "INFO" "Import des données dans $db_name..."

            # Créer un fichier temporaire pour capturer les erreurs
            TEMP_ERROR_FILE=$(mktemp)

            $GUNZIP -c "$sql_file" | $MYSQL --defaults-file="$MYSQL_CNF" "$db_name" 2>"$TEMP_ERROR_FILE"
            RESTORE_STATUS=$?

            # Afficher les erreurs s'il y en a
            if [ -s "$TEMP_ERROR_FILE" ]; then
                cat "$TEMP_ERROR_FILE" >> "$RESTORE_LOG"
            fi
            rm -f "$TEMP_ERROR_FILE"

            if [ $RESTORE_STATUS -eq 0 ]; then
                log_message "OK" "Base $db_name restaurée avec succès"
                DATABASES_RESTORED=$((DATABASES_RESTORED + 1))
            else
                log_message "ERREUR" "Échec de la restauration de la base: $db_name (code: $RESTORE_STATUS)"
                DATABASES_FAILED=$((DATABASES_FAILED + 1))
                TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            fi
        done

        log_message "INFO" "Résumé DB: $DATABASES_RESTORED/$SQL_COUNT bases restaurées, $DATABASES_FAILED échec(s)"
    fi
fi

#==============================================================================
# RESTAURATION DU SITE WEB
#==============================================================================

if [ $RESTORE_WEB -eq 1 ]; then
    log_message "INFO" "------------------------------------------"
    log_message "INFO" "RESTAURATION DU SITE WEB"
    log_message "INFO" "------------------------------------------"

    WEB_ARCHIVE="$BACKUP_DIR/intranet-inside.tar.gz"

    if [ ! -f "$WEB_ARCHIVE" ]; then
        log_message "AVERTISSEMENT" "Archive du site web non trouvée: $WEB_ARCHIVE"
    else
        log_message "INFO" "Restauration du site web vers: $WEB_ROOT"

        # Créer une sauvegarde temporaire du site actuel si il existe
        if [ -d "$WEB_ROOT" ]; then
            TEMP_BACKUP="${WEB_ROOT}_backup_$(date +'%Y%m%d_%H%M%S')"
            log_message "INFO" "Sauvegarde de l'ancien site vers: $TEMP_BACKUP"
            mv "$WEB_ROOT" "$TEMP_BACKUP" 2>&1 | tee -a "$RESTORE_LOG"

            if [ $? -ne 0 ]; then
                log_message "ERREUR" "Impossible de déplacer le site actuel"
                TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            fi
        fi

        # Extraire l'archive
        log_message "INFO" "Extraction de l'archive..."
        $TAR -xzpf "$WEB_ARCHIVE" -C "$(dirname "$WEB_ROOT")" 2>&1 | tee -a "$RESTORE_LOG"

        if [ $? -eq 0 ] && [ -d "$WEB_ROOT" ]; then
            log_message "OK" "Site web restauré avec succès"

            # Restaurer les permissions appropriées
            log_message "INFO" "Ajustement des permissions..."
            chown -R www-data:www-data "$WEB_ROOT" 2>&1 | tee -a "$RESTORE_LOG"
            find "$WEB_ROOT" -type d -exec chmod 755 {} \; 2>&1 | tee -a "$RESTORE_LOG"
            find "$WEB_ROOT" -type f -exec chmod 644 {} \; 2>&1 | tee -a "$RESTORE_LOG"

            log_message "OK" "Permissions ajustées"

            # Supprimer la sauvegarde temporaire si tout s'est bien passé
            if [ -d "$TEMP_BACKUP" ]; then
                log_message "INFO" "Vous pouvez supprimer la sauvegarde temporaire: $TEMP_BACKUP"
            fi
        else
            log_message "ERREUR" "Échec de la restauration du site web"
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))

            # Restaurer l'ancien site si possible
            if [ -d "$TEMP_BACKUP" ]; then
                log_message "INFO" "Restauration de l'ancien site..."
                mv "$TEMP_BACKUP" "$WEB_ROOT" 2>&1 | tee -a "$RESTORE_LOG"
            fi
        fi
    fi
fi

#==============================================================================
# RÉSUMÉ ET FIN
#==============================================================================

log_message "INFO" "=========================================="
log_message "INFO" "RÉSUMÉ DE LA RESTAURATION"
log_message "INFO" "=========================================="

if [ $RESTORE_DB -eq 1 ]; then
    log_message "INFO" "Bases de données restaurées: $DATABASES_RESTORED"
    log_message "INFO" "Bases de données échouées: $DATABASES_FAILED"
fi

if [ $RESTORE_WEB -eq 1 ]; then
    if [ -d "$WEB_ROOT" ]; then
        log_message "INFO" "Site web: Restauré dans $WEB_ROOT"
    else
        log_message "INFO" "Site web: Non restauré"
    fi
fi

log_message "INFO" "Nombre total d'erreurs: $TOTAL_ERRORS"

if [ $TOTAL_ERRORS -eq 0 ]; then
    log_message "OK" "Restauration terminée avec SUCCÈS"
    EXIT_CODE=0
else
    log_message "AVERTISSEMENT" "Restauration terminée avec $TOTAL_ERRORS erreur(s)"
    EXIT_CODE=1
fi

log_message "INFO" "Fin du script - $(date +'%Y-%m-%d %H:%M:%S')"
log_message "INFO" "=========================================="
log_message "INFO" "Log complet disponible dans: $RESTORE_LOG"

# Afficher les actions post-restauration
if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "ACTIONS POST-RESTAURATION RECOMMANDÉES"
    echo "=========================================="

    if [ $RESTORE_WEB -eq 1 ]; then
        echo "✓ Vérifier la configuration Apache"
        echo "  sudo apache2ctl configtest"
        echo "  sudo systemctl restart apache2"
        echo ""
    fi

    if [ $RESTORE_DB -eq 1 ]; then
        echo "✓ Vérifier les connexions aux bases de données"
        echo "✓ Tester le fonctionnement de l'application"
        echo ""
    fi

    echo "✓ Consulter le log de restauration:"
    echo "  cat $RESTORE_LOG"
    echo ""
fi

exit $EXIT_CODE
