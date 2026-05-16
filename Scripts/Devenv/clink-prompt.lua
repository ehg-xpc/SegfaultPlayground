-- Custom Clink prompt with git branch information
-- This file should be copied to %LOCALAPPDATA%\clink\

local function get_git_branch()
    local git_branch = io.popen("git branch --show-current 2>nul"):read("*l")
    if git_branch and git_branch ~= "" then
        return " [" .. git_branch .. "]"
    end
    return ""
end

local function get_git_status()
    local git_status = io.popen("git status --porcelain 2>nul"):read("*a")
    if git_status and git_status ~= "" then
        return "*"  -- Indicate dirty working tree
    end
    return ""
end

local function custom_prompt_filter()
    local cwd = clink.get_cwd()
    local git_branch = get_git_branch()
    local git_dirty = get_git_status()
    
    -- Color codes (ANSI)
    local cyan = "\x1b[36m"
    local green = "\x1b[32m"
    local yellow = "\x1b[33m"
    local red = "\x1b[31m"
    local reset = "\x1b[0m"
    
    -- Build prompt: [path] [branch*]
    -- $ or # for regular/admin
    local prompt = cyan .. cwd .. reset
    
    if git_branch ~= "" then
        local git_color = green
        if git_dirty ~= "" then
            git_color = yellow
        end
        prompt = prompt .. git_color .. git_branch .. git_dirty .. reset
    end
    
    prompt = prompt .. "\n$ "
    
    clink.prompt.value = prompt
    return false
end

-- Register the prompt filter
clink.prompt.register_filter(custom_prompt_filter, 50)
