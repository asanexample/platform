import os
import logging
import datetime
import azure.functions as func
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azure.storage.blob import BlobServiceClient
import time


def main(mytimer: func.TimerRequest) -> None:
    """
    Azure Function to backup Terraform state files.
    This function reads state files from a source storage account and copies them to a backup storage account.

    Args:
        mytimer: The timer trigger event
    """
    # Get settings from environment variables
    source_storage_account = os.environ["SOURCE_STORAGE_ACCOUNT"]
    source_container = os.environ["SOURCE_CONTAINER_NAME"]
    backup_storage_account = os.environ["BACKUP_STORAGE_ACCOUNT"]
    backup_container = os.environ["BACKUP_CONTAINER_NAME"]
    backup_frequency = os.environ.get("BACKUP_FREQUENCY", "daily")
    managed_identity_client_id = os.environ.get(
        "MANAGED_IDENTITY_CLIENT_ID", None)

    # Configure logging
    logging.info(
        f"Starting Terraform state backup - {backup_frequency} backup")

    # Create timestamp folder format
    now = datetime.datetime.now()
    timestamp = now.strftime("%Y%m%d%H%M%S")

    # Determine backup type folder based on date
    yearly_folder = f"yearly/{now.strftime('%Y')}"
    quarterly_folder = f"quarterly/{now.strftime('%Y')}/Q{(now.month-1)//3+1}"
    monthly_folder = f"monthly/{now.strftime('%Y%m')}"
    weekly_folder = f"weekly/{now.strftime('%Y')}/week-{now.strftime('%U')}"
    daily_folder = f"daily/{now.strftime('%Y%m%d')}"

    backup_folder = ""
    if backup_frequency == "daily":
        backup_folder = daily_folder
    elif backup_frequency == "weekly":
        backup_folder = weekly_folder
    elif backup_frequency == "monthly":
        backup_folder = monthly_folder

    # Add quarterly backup on first day of quarter
    if now.day == 1 and now.month in [1, 4, 7, 10]:
        quarterly_backup = True
        backup_folder = quarterly_folder
    else:
        quarterly_backup = False

    # Add yearly backup on first day of year
    if now.day == 1 and now.month == 1:
        yearly_backup = True
        backup_folder = yearly_folder
    else:
        yearly_backup = False

    try:
        # Get managed identity credentials
        if managed_identity_client_id:
            credential = ManagedIdentityCredential(
                client_id=managed_identity_client_id)
        else:
            credential = DefaultAzureCredential()

        # Create clients for source and backup storage accounts
        source_blob_service = BlobServiceClient(
            account_url=f"https://{source_storage_account}.blob.core.windows.net",
            credential=credential
        )
        source_container_client = source_blob_service.get_container_client(
            source_container)

        backup_blob_service = BlobServiceClient(
            account_url=f"https://{backup_storage_account}.blob.core.windows.net",
            credential=credential
        )
        backup_container_client = backup_blob_service.get_container_client(
            backup_container)

        # Check if source container exists
        try:
            source_container_client.get_container_properties()
        except Exception as e:
            logging.error(f"Error accessing source container: {str(e)}")
            raise

        # Initialize counters
        successful_backups = 0
        total_files = 0

        # Get list of all blobs in the source container
        blob_list = list(source_container_client.list_blobs())
        total_files = len(blob_list)

        logging.info(f"Found {total_files} Terraform state files to back up")

        # Loop through each blob and copy to backup
        for blob in blob_list:
            try:
                # Get source blob client
                source_blob = source_container_client.get_blob_client(
                    blob.name)

                # Define backup path
                backup_blob_name = f"{backup_folder}/{blob.name}"

                # Get backup blob client
                backup_blob = backup_container_client.get_blob_client(
                    backup_blob_name)

                # Download from source
                source_data = source_blob.download_blob().readall()

                # Upload to backup
                backup_blob.upload_blob(source_data, overwrite=True)

                logging.info(
                    f"Successfully backed up {blob.name} to {backup_blob_name}")
                successful_backups += 1

                # Add small delay to avoid throttling
                time.sleep(0.2)

            except Exception as e:
                logging.error(f"Error backing up {blob.name}: {str(e)}")

        # Logging summary
        if successful_backups == total_files:
            logging.info(
                f"Backup completed successfully. Backed up {successful_backups} of {total_files} files to {backup_folder}")
        else:
            logging.error(
                f"Backup completed with errors. Backed up {successful_backups} of {total_files} files to {backup_folder}")

        # Log special backup types
        if quarterly_backup:
            logging.info(f"Quarterly backup completed to {quarterly_folder}")
        if yearly_backup:
            logging.info(f"Yearly backup completed to {yearly_folder}")

    except Exception as e:
        logging.error(f"Error in backup operation: {str(e)}")
        raise
