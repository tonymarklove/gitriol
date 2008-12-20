CMD_DEPLOY_USAGE = <<USAGE
gitriol deploy [<commit-ish>]

Deploy changes between the last uploaded commit and the commit supplied. Commit
supplied is taken from, in preference order: command line, 'upload' config
setting, HEAD (with confirmation prompt).
USAGE


CMD_REVERT_USAGE = <<USAGE
gitriol revert (back|date)

Revert to a previous upload specified either 'back' a number of deployments, or
to a specific 'date'. If you are looking to upload an old commit in the git
history that wat never deployed, simply use gitriol deploy.
USAGE


CMD_LOG_USAGE = <<USAGE
gitriol log [OPTIONS]

Show history of deployed commits.

options:
  -l, --limit <num>
    Limit to the most recent <num> deployments. (Default 10)
	
  -a, --all
    Override --limit to show all deployments.
USAGE


CMD_INIT_USAGE = <<USAGE
gitriol init [<commit-ish>]

Deploy all files from the supplied commit, rather than changed files. Most
useful for the initial upload. See help for 'deploy' for alternate ways to
specify the commit.
USAGE


CMD_PASSWORD_USAGE = <<USAGE
gitriol password [OPTIONS]

options:
  -d, --delete
    Delete a password rather than the normal add/change
	
  -p, --project <project>
    Specifiy the project, otherwise you will be asked for it from stdin.
USAGE
