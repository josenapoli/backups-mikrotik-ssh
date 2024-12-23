#!/bin/bash
#
# Mikrotik SSH backup script

LOCAL_DIR=$(dirname "$0")
HOST=$(hostname)
BACKUP_PATH=/FullPath/Mikrotik-backupBackBone-ssh/mikrotik
CONF=$LOCAL_DIR/backupnsmkt.conf
LOG=$LOCAL_DIR/logs/backupnsmkt$(date +%Y%m%d-%T).log
SSH_USER=USER1
SSH_PASS=PASS1
SSH_USER2=USER2
SSH_PASS2=PASS2
DELETE_FILE=yes

# Variables de Correo
TO_ADDRESS="report@domain.com"
BODY="No se registraron problemas durante el proceso de backup"
SUBJECT="Servidor: $HOST - Backup de Mikrotiks finalizo correctamente"
SUBJECT2="Servidor: $HOST - Backup de Mikrotiks finalizo con ERRORES!"
FROM_ADDRESS="sender-permited@domain.com"
MESSAGE="From: ${FROM_ADDRESS}\nTo: ${TO_ADDRESS}\nSubject: ${SUBJECT}\n\n${BODY}"

echo -e "\033[1mScript Backup Mikrotik via SSH\033[0m"
echo ""

if [ ! -f "$CONF" ] 2>/dev/null; then
    echo -e "\e[31m!!!ERROR\e[0m, Archivo de configuracion no encontrado!"
    exit 1
fi

if [ ! -d "$BACKUP_PATH" ]; then
    echo -e "\e[31m!!!ERROR\e[0m, Ruta de backup no encontrada!"
    exit 1
fi

LAST_CHAR=$(tail -c 1 "$CONF")
if [ "$LAST_CHAR" != "" ]; then
    echo -e "" >>$CONF
fi

INDEX=0
SCP_ERROR=no
FAILED_EQUIPMENT=""

while read -r line; do
    line=$(echo "$line" | grep :)
    if [ -n "$line" ]; then
        if [ "${line:0:1}" != "#" ]; then
            IP[$INDEX]=$(echo "$line" | cut -d: -f1 | tr -d " ")
            DESC[$INDEX]=$(echo "$line" | cut -d: -f2 | tr -d " ")
            if [ ! -d "${BACKUP_PATH}/${DESC[$INDEX]}" ]; then
                mkdir -p "${BACKUP_PATH}/${DESC[$INDEX]}"
            fi
            INDEX=$((INDEX + 1))
        fi
    fi
done <"$CONF"

cmd="/system package print file=backupmkt.txt; /export file=backupmkt.rsc; /system backup save name=backupmkt.backup;"
echo "$cmd" >$LOG
echo "--------------------------------------------------------------------------------" >>$LOG

# Function to attempt SSH connection with multiple credentials
attempt_ssh_connection() {
    local ip=$1
    local cmd=$2
    if timeout 50s sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-dss -o KexAlgorithms=diffie-hellman-group14-sha1 "$SSH_USER@$ip" "$cmd" >/dev/null 2>&1; then
        echo "$SSH_USER" "$SSH_PASS" "primera credencial"
    else
        echo "!!! Conexion SSH fallo con la primera credencial!" >>$LOG
        if timeout 50s sshpass -p "$SSH_PASS2" ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-dss -o KexAlgorithms=diffie-hellman-group14-sha1 "$SSH_USER2@$ip" "$cmd" >/dev/null 2>&1; then
            echo "$SSH_USER2" "$SSH_PASS2" "segunda credencial"
        else
            echo "!!! Conexion SSH fallo con la segunda credencial!" >>$LOG
            echo ""
        fi
    fi
}

# Function to attempt SCP transfer with the given credentials
attempt_scp_transfer() {
    local user=$1
    local pass=$2
    local ip=$3
    local file=$4
    local dest=$5
    timeout 45s sshpass -p "$pass" scp -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-dss -o KexAlgorithms=diffie-hellman-group14-sha1 "$user@$ip:/$file" "$dest" >/dev/null 2>&1
}

for ((a = 0; a < INDEX; a++)); do
    echo "${IP[$a]} -  ${DESC[$a]}"
    echo "${IP[$a]} -  ${DESC[$a]}" >>$LOG

    credentials=$(attempt_ssh_connection "${IP[$a]}" "$cmd")
    if [ -n "$credentials" ]; then
        read -r user pass cred_label <<<"$credentials"
        echo -e " \e[32mOK\e[0m Conexion SSH establecida con $cred_label."
        echo "!!! Conexion SSH establecida con $cred_label en ${IP[$a]}" >>$LOG
    else
        echo -e " \e[31mErr\e[0m Conexion SSH fallo!"
        echo "!!! Conexion SSH fallo!" >>$LOG
        SCP_ERROR=yes
        FAILED_EQUIPMENT+="${DESC[$a]} (${IP[$a]})\n"
        continue
    fi

    sleep 2

    for SCPFILE in backupmkt.backup backupmkt.rsc backupmkt.txt; do
        if attempt_scp_transfer "$user" "$pass" "${IP[$a]}" "$SCPFILE" "${BACKUP_PATH}/${DESC[$a]}/"; then
            echo -e " \e[32mOK\e[0m  Transferencia desde ${DESC[$a]} completa."
            echo "!!! Transferencia desde ${DESC[$a]} completa con $cred_label" >>$LOG
            mv "${BACKUP_PATH}/${DESC[$a]}/${SCPFILE}" "${BACKUP_PATH}/${DESC[$a]}/$(date +%Y%m%d-%T)-${SCPFILE}"
            if [ "$DELETE_FILE" == "yes" ]; then
                timeout 45s sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@${IP[$a]}" "file remove $SCPFILE" >/dev/null 2>&1
                if [ $? -ne 0 ]; then
                    echo -e " \e[31mErr\e[0m Borrado de archivo ${DESC[$a]} fallo!"
                    echo "!!! Borrado de archivo ${DESC[$a]} fallo!" >>$LOG
                else
                    echo -e " \e[32mOK\e[0m Archivo ${DESC[$a]} en el Mikrotik borrado."
                    echo "!!! Archivo ${DESC[$a]} en el Mikrotik borrado!" >>$LOG
                fi
            fi
        else
            echo -e " \e[31mErr\e[0m Transferencia desde ${DESC[$a]} fallo!"
            echo "!!! Transferencia desde ${DESC[$a]} fallo con $cred_label" >>$LOG
            SCP_ERROR=yes
            FAILED_EQUIPMENT+="${DESC[$a]} (${IP[$a]})\n"
        fi
    done
done

echo "--------------------------------------------------------------------------------" >>$LOG
echo "$(date)" >>$LOG
echo "--------------------------------------------------------------------------------" >>$LOG

# Send success or failure email notification
echo -e "\nEnviando notificacion por email..."
if [ "$SCP_ERROR" == "yes" ]; then
    BODY2="!!!ERROR - Cuando un backup se copiaba ocurrio un ERROR.\nRevisar el archivo de log del servidor para $HOST: $LOG\n\nEquipos que fallaron:\n$FAILED_EQUIPMENT"
    MESSAGE2="From: ${FROM_ADDRESS}\nTo: ${TO_ADDRESS}\nSubject: ${SUBJECT2}\n\n${BODY2}
    echo -e "$MESSAGE2" | msmtp -a default -t
    echo -e " \e[31mErr\e[0m Email de error enviado!"
    echo "!!! Email de error enviado!" >>$LOG
else
    echo -e "$MESSAGE" | msmtp -a default -t
    echo -e " \e[32mOK\e[0m Email de éxito enviado!"
    echo "!!! Email de éxito enviado!" >>$LOG
fi

echo "--------------------------------------------------------------------------------"
echo -e "\033[1mProceso de Backup finalizado!\033[0m"
echo "--------------------------------------------------------------------------------"
