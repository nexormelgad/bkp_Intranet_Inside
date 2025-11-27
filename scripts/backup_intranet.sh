#!/bin/bash
################################################################################
# Script de sauvegarde automatique pour VPS Debian/Ubuntu
#
# Fonctionnement :
# - Crée un dossier de sauvegarde unique par exécution (format: YYYYMMDD_HHMM)
# - Sauvegarde toutes les bases MySQL utilisateur (exclut les bases système)
# - Sauvegarde le répertoire web /var/www/intranet-inside
# - Génère un log détaillé dans chaque dossier de sauvegarde
# - Gère la rotation automatique des anciennes sauvegardes
#
# Utilisation :
#   /mnt/backup/scripts/backup_intranet.sh
#
# Prérequis :
#   - Fichier /root/.my.cnf avec les credentials MySQL :
#       [client]
#       user=backupuser
#       password=MotDePasse
#
# Auteur : Script généré pour sauvegarde VPS OVH
# Date : 2025-11-27
################################################################################

set -o pipefail

#==============================================================================
# CONFIGURATION - Modifier selon vos besoins
#==============================================================================

# Répertoire racine des sauvegardes
BACKUP_ROOT="/mnt/backup"

# Répertoire du site web à sauvegarder
WEB_ROOT="/var/www/intranet-inside"

# Nombre de jours de rétention des sauvegardes (les plus anciennes seront supprimées)
RETENTION_DAYS=8

# Fichier de configuration MySQL
MYSQL_CNF="/root/.my.cnf"

#==============================================================================
# VARIABLES INTERNES - Ne pas modifier
#==============================================================================

# Nom du dossier de sauvegarde pour cette exécution (format: YYYYMMDD_HHMM)
RUN_DIR="$BACKUP_ROOT/$(date +'%Y%m%d_%H%M')"

# Fichier de log pour cette exécution
LOGFILE="$RUN_DIR/backup.log"

# Chemins des commandes
MYSQL="/usr/bin/mysql"
MYSQLDUMP="/usr/bin/mysqldump"
TAR="/bin/tar"
GZIP="/bin/gzip"
FIND="/usr/bin/find"

# Compteurs
TOTAL_ERRORS=0
DATABASES_BACKED_UP=0
DATABASES_FAILED=0

#==============================================================================
# FONCTIONS UTILITAIRES
#==============================================================================

# Fonction d'affichage avec timestamp
log_message() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*"
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

# Fonction de nettoyage en cas d'erreur critique
cleanup_on_error() {
    log_message "ERREUR" "Arrêt du script suite à une erreur critique"
    log_message "INFO" "Fin du script (avec erreurs) - $(date +'%Y-%m-%d %H:%M:%S')"
    exit 1
}

#==============================================================================
# INITIALISATION
#==============================================================================

# Créer le dossier de sauvegarde pour cette exécution
mkdir -p "$RUN_DIR"
if [ $? -ne 0 ]; then
    echo "[ERREUR] Impossible de créer le répertoire de sauvegarde: $RUN_DIR"
    exit 1
fi

# Rediriger toutes les sorties vers le fichier de log
exec > >(tee -a "$LOGFILE") 2>&1

log_message "INFO" "=========================================="
log_message "INFO" "Début de la sauvegarde"
log_message "INFO" "=========================================="
log_message "INFO" "Dossier de sauvegarde: $RUN_DIR"
log_message "INFO" "Rétention configurée: $RETENTION_DAYS jours"

#==============================================================================
# VÉRIFICATIONS PRÉALABLES
#==============================================================================

log_message "INFO" "Vérification des prérequis..."

# Vérifier les commandes nécessaires
MISSING_COMMANDS=0
for cmd in "$MYSQL" "$MYSQLDUMP" "$TAR" "$GZIP" "$FIND"; do
    if ! check_command "$cmd"; then
        MISSING_COMMANDS=$((MISSING_COMMANDS + 1))
    fi
done

if [ $MISSING_COMMANDS -gt 0 ]; then
    log_message "ERREUR" "$MISSING_COMMANDS commande(s) manquante(s). Installation requise."
    cleanup_on_error
fi

# Vérifier le fichier de configuration MySQL
if [ ! -f "$MYSQL_CNF" ]; then
    log_message "ERREUR" "Fichier de configuration MySQL non trouvé: $MYSQL_CNF"
    log_message "INFO" "Créez le fichier avec les credentials MySQL:"
    log_message "INFO" "  [client]"
    log_message "INFO" "  user=backupuser"
    log_message "INFO" "  password=MotDePasse"
    cleanup_on_error
fi

# Vérifier que le répertoire web existe
if [ ! -d "$WEB_ROOT" ]; then
    log_message "AVERTISSEMENT" "Répertoire web non trouvé: $WEB_ROOT"
    log_message "AVERTISSEMENT" "La sauvegarde du site web sera ignorée"
fi

log_message "OK" "Vérifications préalables terminées avec succès"

#==============================================================================
# SAUVEGARDE DES BASES DE DONNÉES MYSQL
#==============================================================================

log_message "INFO" "------------------------------------------"
log_message "INFO" "SAUVEGARDE DES BASES DE DONNÉES MYSQL"
log_message "INFO" "------------------------------------------"

# Récupérer la liste des bases de données (en excluant les bases système)
log_message "INFO" "Récupération de la liste des bases de données..."
DATABASES=$($MYSQL --defaults-file="$MYSQL_CNF" -N -e "SHOW DATABASES;" 2>/dev/null | egrep -v "^(information_schema|performance_schema|mysql|sys)$")

if [ $? -ne 0 ]; then
    log_message "ERREUR" "Impossible de se connecter à MySQL ou de récupérer la liste des bases"
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
else
    # Compter le nombre de bases
    DB_COUNT=$(echo "$DATABASES" | wc -l)

    if [ -z "$DATABASES" ] || [ "$DB_COUNT" -eq 0 ]; then
        log_message "AVERTISSEMENT" "Aucune base de données utilisateur trouvée"
    else
        log_message "INFO" "Nombre de bases de données à sauvegarder: $DB_COUNT"

        # Sauvegarder chaque base de données
        for DB in $DATABASES; do
            log_message "INFO" "Sauvegarde de la base: $DB"

            DUMP_FILE="$RUN_DIR/${DB}.sql.gz"

            # Effectuer le dump avec compression
            $MYSQLDUMP --defaults-file="$MYSQL_CNF" \
                       --single-transaction \
                       --quick \
                       --routines \
                       --events \
                       --triggers \
                       --skip-lock-tables \
                       "$DB" 2>/dev/null | $GZIP > "$DUMP_FILE"

            if [ $? -eq 0 ] && [ -f "$DUMP_FILE" ] && [ -s "$DUMP_FILE" ]; then
                # Calculer la taille du fichier
                FILE_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
                log_message "OK" "Base $DB sauvegardée avec succès ($FILE_SIZE)"
                DATABASES_BACKED_UP=$((DATABASES_BACKED_UP + 1))
            else
                log_message "ERREUR" "Échec de la sauvegarde de la base: $DB"
                # Supprimer le fichier incomplet s'il existe
                [ -f "$DUMP_FILE" ] && rm -f "$DUMP_FILE"
                DATABASES_FAILED=$((DATABASES_FAILED + 1))
                TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            fi
        done

        log_message "INFO" "Résumé MySQL: $DATABASES_BACKED_UP/$DB_COUNT bases sauvegardées, $DATABASES_FAILED échec(s)"
    fi
fi

#==============================================================================
# SAUVEGARDE DU SITE WEB
#==============================================================================

log_message "INFO" "------------------------------------------"
log_message "INFO" "SAUVEGARDE DU SITE WEB"
log_message "INFO" "------------------------------------------"

if [ -d "$WEB_ROOT" ]; then
    log_message "INFO" "Sauvegarde du répertoire: $WEB_ROOT"

    WEB_ARCHIVE="$RUN_DIR/intranet-inside.tar.gz"

    # Créer l'archive tar.gz avec préservation des permissions
    $TAR -czpf "$WEB_ARCHIVE" -C "$(dirname "$WEB_ROOT")" "$(basename "$WEB_ROOT")" 2>&1

    if [ $? -eq 0 ] && [ -f "$WEB_ARCHIVE" ] && [ -s "$WEB_ARCHIVE" ]; then
        # Calculer la taille de l'archive
        ARCHIVE_SIZE=$(du -h "$WEB_ARCHIVE" | cut -f1)
        log_message "OK" "Site web sauvegardé avec succès ($ARCHIVE_SIZE)"
    else
        log_message "ERREUR" "Échec de la sauvegarde du site web"
        # Supprimer l'archive incomplète si elle existe
        [ -f "$WEB_ARCHIVE" ] && rm -f "$WEB_ARCHIVE"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    fi
else
    log_message "AVERTISSEMENT" "Répertoire web inexistant, sauvegarde ignorée: $WEB_ROOT"
fi

#==============================================================================
# ROTATION DES SAUVEGARDES
#==============================================================================

log_message "INFO" "------------------------------------------"
log_message "INFO" "ROTATION DES SAUVEGARDES"
log_message "INFO" "------------------------------------------"

log_message "INFO" "Suppression des sauvegardes de plus de $RETENTION_DAYS jours..."

# Compter les dossiers qui seront supprimés
OLD_BACKUPS=$($FIND "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +$RETENTION_DAYS 2>/dev/null | wc -l)

if [ "$OLD_BACKUPS" -gt 0 ]; then
    log_message "INFO" "Nombre de sauvegardes anciennes trouvées: $OLD_BACKUPS"

    # Supprimer les anciennes sauvegardes
    $FIND "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>&1

    if [ $? -eq 0 ]; then
        log_message "OK" "Rotation terminée: $OLD_BACKUPS dossier(s) supprimé(s)"
    else
        log_message "ERREUR" "Erreur lors de la rotation des sauvegardes"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    fi
else
    log_message "INFO" "Aucune sauvegarde ancienne à supprimer"
fi

# Afficher l'espace disque utilisé
log_message "INFO" "Espace disque utilisé pour les sauvegardes:"
du -sh "$BACKUP_ROOT" 2>/dev/null | while read size path; do
    log_message "INFO" "  Total: $size"
done

#==============================================================================
# RÉSUMÉ ET FIN
#==============================================================================

log_message "INFO" "=========================================="
log_message "INFO" "RÉSUMÉ DE LA SAUVEGARDE"
log_message "INFO" "=========================================="
log_message "INFO" "Dossier de sauvegarde: $RUN_DIR"
log_message "INFO" "Bases de données sauvegardées: $DATABASES_BACKED_UP"
log_message "INFO" "Bases de données échouées: $DATABASES_FAILED"

# Vérifier si l'archive web existe
if [ -f "$RUN_DIR/intranet-inside.tar.gz" ]; then
    log_message "INFO" "Site web: Sauvegardé"
else
    log_message "INFO" "Site web: Non sauvegardé"
fi

log_message "INFO" "Nombre total d'erreurs: $TOTAL_ERRORS"

if [ $TOTAL_ERRORS -eq 0 ]; then
    log_message "OK" "Sauvegarde terminée avec SUCCÈS"
    EXIT_CODE=0
else
    log_message "AVERTISSEMENT" "Sauvegarde terminée avec $TOTAL_ERRORS erreur(s)"
    EXIT_CODE=1
fi

log_message "INFO" "Fin du script - $(date +'%Y-%m-%d %H:%M:%S')"
log_message "INFO" "=========================================="

exit $EXIT_CODE
