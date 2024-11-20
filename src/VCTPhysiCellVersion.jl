using SQLite

function physicellVersionID()
    if !physicellIsGit()
        tag = readlines(joinpath(physicell_dir, "VERSION.txt"))[1]
        df = DBInterface.execute(db, "INSERT OR IGNORE INTO physicell_versions commit_hash VALUES '$(tag)-download' RETURNING phsyicell_version_id;") |> DataFrame
        if isempty(df)
            query = constructSelectQuery("physicell_versions", "WHERE commit_hash='$(tag)-download'"; selection="physicell_version_id")
            df = queryToDataFrame(query; is_row=true)
        end
        return df.physicell_version_id[1]
    end

    if !gitDirectoryIsClean(physicell_dir)
        println("""
        PhysiCell repo is dirty. Not adding version to database.
        Make a new commit or stash changes to clean the repo.
        """
        )
        return missing
    end

    # then, get the current commit hash
    commit_hash = readchomp(`git -C $physicell_dir rev-parse HEAD`)

    # then, compare that hash with hashes in the database
    query = constructSelectQuery("physicell_versions", "WHERE commit_hash = '$commit_hash'")
    current_entry_df = queryToDataFrame(query)
    @assert size(current_entry_df, 1) <= 1 "The database should have unique 'commit_hash' entries."
    is_hash_in_db = !isempty(current_entry_df)
    no_entries_missing = is_hash_in_db && all(.!ismissing.([x[1] for x in eachcol(current_entry_df)]))
    if no_entries_missing
        # if the commit hash is already in the database, and it has a tag, then we are done
        return current_entry_df.physicell_version_id[1]
    end
    entry_dict = Dict{String,String}()
    
    # then, compare that hash with remote hashes to identify the tag, repo owner, and date
    hash_to_tag_dict = getCommitHashToTagDict(physicell_dir)
    if haskey(hash_to_tag_dict, commit_hash)
        entry_dict["tag"] = hash_to_tag_dict[commit_hash]
    else
        entry_dict["tag"] = "NULL"
    end
    
    entry_dict["repo_owner"] = repoOwner(commit_hash, entry_dict["tag"])
    entry_dict["date"] = readchomp(`git -C $physicell_dir show -s --format=%ci $commit_hash`)
    
    db_entry_dict = [k => v=="NULL" ? v : "'$v'" for (k,v) in entry_dict] |> Dict # surround non-NULL values with single quotes, so NULL really go in as NULL
    if is_hash_in_db
        for (name, col) in pairs(eachcol(current_entry_df))
            if !ismissing(col[1])
                continue
            end
            name_str = string(name)
            DBInterface.execute(db, "UPDATE physicell_versions SET $(name_str) = $(db_entry_dict[name_str]) WHERE commit_hash = '$commit_hash';")
        end
        query = constructSelectQuery("physicell_versions", "WHERE commit_hash = '$commit_hash'"; selection="physicell_version_id")
        df = queryToDataFrame(query; is_row=true)
    else
        df = DBInterface.execute(db, "INSERT INTO physicell_versions (commit_hash, tag, repo_owner, date) VALUES ('$commit_hash', $(db_entry_dict["tag"]), $(db_entry_dict["repo_owner"]), $(db_entry_dict["date"])) RETURNING physicell_version_id;") |> DataFrame
    end
    return df.physicell_version_id[1]
end

function physicellIsGit()
    is_git = isdir(joinpath(physicell_dir, ".git"))
    if !is_git # possible it is a submodule
        path_to_file = joinpath(physicell_dir, ".git")
        if isfile(path_to_file)
            lines = readlines(path_to_file)
            if length(lines) > 0
                line_1 = lines[1]
                is_git = startswith(line_1, "gitdir: ") &&
                         contains(line_1, "modules") &&
                         endswith(line_1, "PhysiCell")
            end
        end
    end
    return is_git
end

function gitDirectoryIsClean(dir::String)
    cmd = `git -C $dir status --porcelain` # -C flag is for changing directory, --porcelain flag is for machine-readable output (much easier to tell if clean this way)
    output = read(cmd, String)
    return length(output) == 0
end

function getCommitHashToTagDict(dir::String)
    hash_to_tag_dict = Dict{String, String}()
    has_tags = !isempty(readchomp(`git -C $dir tag`))
    if !has_tags
        return hash_to_tag_dict
    end
    tags_output = readchomp(`git -C $dir show-ref --tags`)
    tags = split(tags_output, "\n")
    for tag in tags
        parts = split(tag)
        if length(parts) == 2
            commit_hash, tag_ref = parts
            tag_name = split(tag_ref, '/')[end]
            hash_to_tag_dict[commit_hash] = tag_name
        else
            println("Error: tag is not in the expected format (<commit_hash> <tag_ref>):\n\t$tag")
        end
    end
    return hash_to_tag_dict
end

function repoOwner(commit_hash, tag::String)
    if tag == "NULL"
        return "NULL"
    end
    remotes = gitRemotes(physicell_dir)
    for remote in remotes
        remote_hash_tags = readchomp(`git -C $physicell_dir ls-remote --tags $remote`)
        remote_hash_tags = split(remote_hash_tags, "\n")
        for remote_hash_tag in remote_hash_tags
            remote_commit_hash, remote_tag_name = split(remote_hash_tag, "\t")
            if remote_commit_hash != commit_hash
                continue
            end
            remote_tag_name = split(remote_tag_name, "/")[end]
            if remote_tag_name == tag
                remote_url = readchomp(`git -C $physicell_dir remote get-url $remote`)
                repo_owner = split(remote_url, "/")[end-1]
                return repo_owner
            end
        end
    end
    return "NULL"
end

function gitRemotes(dir::String)
    remotes_output = readchomp(`git -C $dir remote`)
    remotes = split(remotes_output, "\n")
    return remotes
end

function physicellVersion()
    if ismissing(current_physicell_version_id)
        return "Current PhysiCell repository is a dirty git repo. Not recording version in database."
    end
    query = constructSelectQuery("physicell_versions", "WHERE physicell_version_id = $(current_physicell_version_id)")
    df = queryToDataFrame(query; is_row=true)
    str_begin = ismissing(df.repo_owner[1]) ? "" : "($(df.repo_owner[1])) "
    str_middle = ismissing(df.tag[1]) ? df.commit_hash[1] : df.tag[1]
    str_end = ismissing(df.date[1]) ? "" : " COMMITTED ON $(df.date[1])"
    return "$str_begin$str_middle$str_end"
end

function physicellVersionDBEntry()
    return ismissing(current_physicell_version_id) ? "NULL" : current_physicell_version_id
end