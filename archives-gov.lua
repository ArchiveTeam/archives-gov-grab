dofile("urlcode.lua")
dofile("table_show.lua")
JSON = (loadfile "JSON.lua")()

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local items = {}
local discousers = {}
local discovideos = {}
local discotags = {}

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

start, end_ = string.match(item_value, "([0-9]+)-([0-9]+)")
for i = start, end_ do
  items[i] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url)
  if string.match(url, "'+")
     or string.match(url, "[<>\\]")
     or string.match(url, "//$") then
    return false
  end

  for s in string.gmatch(url, "([0-9]+)") do
    if items[tonumber(s)] == true then
      return true
    end
  end

  return false
end

sorted = function(t)
  local t_sorted = {}
  for n in pairs(t) do
    table.insert(t_sorted, n)
  end
  table.sort(t_sorted)
  return t_sorted
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, '"') then
    return false
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
     and (allowed(url) or html == 0) then
    addedtolist[url] = true
    return true
  else
    return false
  end
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true

  local function merge_query_strings(newurl, t)
    for _, arg in ipairs(sorted(t)) do
      newurl = newurl .. arg .. "=" .. t[arg] .. "&"
    end
    if string.match(newurl, "^.+&$") then
      newurl = string.match(newurl, "^(.+)&$")
    end
    return newurl
  end

  local function basic_search(surl)
    local query_strings = {}

    query_strings["action"] = "search"
    query_strings["facet"] = "true"
    query_strings["facet.fields"] = "tabType"
    query_strings["noSpinner"] = "true"
    query_strings["offset"] = "0"
    query_strings["rows"] = "0"
    query_strings["tabType"] = "all"

    for query_string in string.gmatch(string.match(surl, "%?(.+)$"), "([^&]+)") do
      if not (string.match(query_string, "offset=") or string.match(query_string, "tabType=")) then
        local arg, val = string.match(query_string, "^(.+)=(.+)$")
        query_strings[arg] = val
      end
    end

    check(merge_query_strings("https://catalog.archives.gov/OpaAPI/iapi/v1?", query_strings))
  end

  local function specific_search(surl)
    local query_strings = {}

    query_strings["action"] = "search"
    query_strings["facet"] = "true"
    query_strings["facet.fields"] = "oldScope,level,materialsType,fileFormat,locationIds,dateRangeFacet"
    query_strings["highlight"] = "true"
    query_strings["rows"] = "20"
    if not string.match(surl, "offset=[0-9]+") then
      query_strings["offset"] = "0"
    end
    if not string.match(surl, "tabType=[a-z]+") then
      query_strings["tabType"] = "all"
    end

    for query_string in string.gmatch(string.match(surl, "%?(.+)$"), "([^&]+)") do
      local arg, val = string.match(query_string, "^(.+)=(.+)$")
      query_strings[arg] = val
    end

    check(merge_query_strings("https://catalog.archives.gov/OpaAPI/iapi/v1?", query_strings))

    if not (string.match(surl, "offset=[0-9]+") or string.match(surl, "tabType=[a-z]+")) then
      check(surl .. "&tabType=all")
      check(surl .. "&tabType=online")
      check(surl .. "&tabType=web")
      check(surl .. "&tabType=document")
      check(surl .. "&tabType=image")
      check(surl .. "&tabType=video")
      check(surl .. "&offset=0")
      check(surl .. "&offset=0&tabType=all")
      check(surl .. "&offset=0&tabType=online")
      check(surl .. "&offset=0&tabType=web")
      check(surl .. "&offset=0&tabType=document")
      check(surl .. "&offset=0&tabType=image")
      check(surl .. "&offset=0&tabType=video")
    end
  end

  function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local urlextract = string.gsub(string.gsub(url, "&amp;", "&"), " ", "+")

    if string.match(urlextract, "^https?://catalog%.archives%.gov/search%?") then
      basic_search(urlextract)
      specific_search(urlextract)
    end
      
    if (downloaded[url] ~= true and addedtolist[url] ~= true)
       and allowed(url) then
      table.insert(urls, { url=string.gsub(url, "&amp;", "&") })
      addedtolist[url] = true
      addedtolist[string.gsub(url, "&amp;", "&")] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end
  
  if allowed(url) then
    html = read_file(file)

    if string.match(url, "^https?://catalog%.archives%.gov/[^/]*/?iapi/v1.+$") then
      local start = string.match(url, "^(https?://catalog%.archives%.gov/)[^/]*/?iapi/v1.+$")
      local end_ = string.match(url, "^https?://catalog%.archives%.gov/[^/]*/?(iapi/v1.+)$")
      check(start .. end_)
      check(start .. "OpaAPI/" .. end_)
    end

    if string.match(url, "^https?://catalog%.archives%.gov/[^/]*/?iapi/v1/id/[0-9]+$") then
      local itemid = string.match(url, "/id/([0-9]+)$")
      for path in string.gmatch(html, '"@path"%s*:%s*"([^"]+)"') do
        if string.match(path, "^\\?/") then
          checknewurl(path)
        else
          checknewurl("https:\\/\\/catalog.archives.gov\\/OpaAPI\\/media\\/" .. itemid .. "\\/" .. path)
          checknewurl("https:\\/\\/catalog.archives.gov\\/OpaAPI\\/media\\/" .. itemid .. "\\/" .. path .. "?download=true")
          checknewurl("https:\\/\\/catalog.archives.gov\\/OpaAPI\\/media\\/" .. itemid .. "\\/" .. path .. "?download=false")
        end
      end
    end

    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, 'href="([^"]+)"') do
      checknewshorturl(newurl)
    end
  end

  return urls
end
  

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404 and status_code ~= 410) or
    status_code == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"]) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local file = io.open(item_dir..'/'..warc_file_base..'_data.txt', 'w')
  for user, _ in pairs(discousers) do
    file:write("user:" .. user .. "\n")
  end
  for video, _ in pairs(discovideos) do
    file:write("video:" .. video .. "\n")
  end
  for tag, _ in pairs(discotags) do
    file:write("tag:" .. tag .. "\n")
  end
  file:close()
end