# docker-s3-backup-restore
A utility docker image to backup or restore another container's data to s3.

## Usage
The container is designed to use arguments configure the container.

The only other configuration is the generated backup.yml file. The backup.yml file is used to specify the path and which aws-cli options the container should use.

The script values backup speed/time and low cpu utilization over s3 space usage. The strategy is to sync the data instead performing a full backup every time. The files are copied as is to S3 to a date and time stamp folder. if a previous backup exist it's copied remotely before the local copy is synced.

```
Options:
    --config <path>
                Path to read or write configuration file .
                Default: /data/backup.yml

    --region <string>
                The AWS region to use.

    --access-key <string>
                AWS Access Key

    --secret-key <string>
                AWS Secret Key

    --mode <string>
                init - create the empty configuration file in the /data/backup.json path
                restore - reads the /data/backup.yml file and executes a restore
                backup - reads the /data/backup.yml file and executes a save

    --timestamp <string>
                When performing a restore. Specify a timestamp to restore
```

## Examples

Get help
```SHELL
docker run -it --rm --volumes-from <other container id/name with the data> ceaser/s3-backup-restore
```
Create a empty backup.yml file. In the /data directory
```SHELL
docker run -it --rm --volumes-from <other container id/name with the data> ceaser/s3-backup-restore --mode init --config /data/backup.yml
```
How to Backup. Security credentials are omitted.
```SHELL
docker run -it --rm --volumes-from <other container id/name with the data> ceaser/s3-backup-restore --mode backup
```
How to Restore. Security credentials are omitted.
```SHELL
docker run -it --rm --volumes-from <other container id/name with the data> ceaser/s3-backup-restore --mode restore
```

