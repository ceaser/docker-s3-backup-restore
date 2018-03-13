# docker-s3-backup-restore
A utility docker image to backup or restore another container's data to s3.

## Usage
The container is designed to use arguments configure the container.

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
                restore - reads the /data/backup.yml file and executes a restore
                backup - reads the /data/backup.yml file and executes a save

    --local <string>
                Path to the local directory to backup.
                Default: /data/

    --remote <string>
                S3 bucket and path to use. Must start with the s3:// prefix.

    --owner <string>
                The owner name or id to change restored files to.
                Default: 1000

    --group <string>
                The group  name or id to change restored files to.
                Default: 1000

    --timestamp <string>
                When performing a restore. Specify a timestamp to restore

    -- <string>
                Additional arguments to pass to the AWS cli. Common use cases are --include, --exclude and --storage-class

```

## Examples

Get help
```SHELL
docker run --rm ceaser/s3-backup-restore
```

How to Backup. Security credentials are omitted.
```SHELL
docker run -it --rm --volumes-from <other container id/name with the data> ceaser/s3-backup-restore --mode backup --remote s3://bucket/path
```

How to Restore. Security credentials are omitted.
```SHELL
docker run -it --rm --volumes-from <other container id/name with the data> ceaser/s3-backup-restore --mode restore --remote s3://bucket/path
```

