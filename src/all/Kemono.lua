-- {"id":93278,"ver":"1.1.3","libVer":"1.0.0","author":"TechnoJo4","dep":["url>=1.0.0","dkjson>=1.0.0"]}

local baseURL = "https://pawchive.pw/"
local apiURL = baseURL .. "/api/v1"

local json = Require("dkjson")

local SERVICES = {
    ["patreon"] = "Patreon",
    ["fanbox"] = "Pixiv Fanbox",
    ["fantia"] = "Fantia",
    ["afdian"] = "Afdian",
    ["boosty"] = "Boosty",
    ["gumroad"] = "Gumroad",
    ["subscribestar"] = "SubscribeStar",
    ["dlsite"] = "DLsite"
}

local descriptionFormat = "Service: %s"
    .. "\nProfile ID: %s"

local _creators

-- kemono is currently serving JSON as text/css for... reasons?
local headers = HeadersBuilder():add("Accept", "text/css"):build()
local function jsonGET(url)
    local res = Request(GET(url, headers))
    return json.decode(res:body():string())
end

-- /creators is the full list (~96k entries, ~15 MB) with no server-side paging.
-- Decoding it with dkjson is far too slow on a phone, so pull out only the
-- fields we need with a pattern, then page through it locally.
local CREATOR_PATTERN = '{"id":"([^"]*)","name":"(.-)","public_id":.-,"service":"([^"]*)".-"favorited":(%d+)'
local PER_PAGE = 50

local function creators()
    if not _creators then
        local body = Request(GET(apiURL .. "/creators", headers)):body():string()
        local list = {}
        for id, name, service, favorited in body:gmatch(CREATOR_PATTERN) do
            list[#list+1] = {
                id = id,
                name = (name:gsub("\\(.)", "%1")),
                service = service,
                favorited = tonumber(favorited)
            }
        end
        table.sort(list, function(a, b) return a.favorited > b.favorited end)
        _creators = list
    end
    return _creators
end

local function pageOf(list, page)
    local out = {}
    local first = (page - 1) * PER_PAGE + 1
    for i = first, math.min(first + PER_PAGE - 1, #list) do
        out[#out+1] = list[i]
    end
    return out
end

local function shrinkURL(url)
    return url:gsub("^.-kemono%.party/?", "")
        :gsub("^.-kemono%.su/?", "")
        :gsub("^.-kemono%.cr/?", "")
        :gsub("^.-pawchive%.pw/?", "")
end

local function expandURL(url)
    return baseURL .. url
end

local function creatorURL(v)
    return "/" .. v.service .. "/user/" .. v.id
end

local function parseListing(tbl)
    return map(tbl, function(v)
        return Novel {
            title = v.name,
            link = creatorURL(v),
            imageURL = baseURL .. "/banners/" .. v.service .. "/" .. v.id
        }
    end)
end

return {
    id = 93278,
    name = "Pawchive",
    baseURL = baseURL,
    imageURL = "https://pawchive.pw/static/logo.png",
    hasSearch = true,
    startIndex = 1,
    chapterType = ChapterType.HTML,

    listings = {
        Listing("All", true, function(data)
            return parseListing(pageOf(creators(), data[PAGE]))
        end),
        Listing("Favorites", false, function(data)
            return parseListing(jsonGET(apiURL .. "/account/favorites"))
        end)
    },

    getPassage = function(chapterURL)
        local res = jsonGET(apiURL .. chapterURL)
        -- the API used to wrap the post as { post = {...} }; it now returns the post directly
        local content = (res.post or res).content or ""
        return "<!DOCTYPE html><html><head></head><body>" .. content .. "</body></html>"
    end,

    parseNovel = function(novelURL, loadChapters)
        -- fetch just this creator's profile; the full /creators list is ~15 MB
        -- and too slow to download and parse on a phone
        local creator = jsonGET(apiURL .. novelURL .. "/profile")

        local info = NovelInfo {
            title = creator.name,
            imageURL = baseURL .. "/icons/" .. creator.service .. "/" .. creator.id,
            description = string.format(descriptionFormat, creator.service, creator.id)
        }

        if loadChapters then
            local o = 0
            local posts = {}
            while true do
                local page = jsonGET(apiURL .. novelURL .. "/posts?o="..tostring(o))
                if not page or #page == 0 then break end
                o = o + 50
                posts[#posts+1] = page
            end

            posts = flatten(posts)
            info:setChapters(AsList(filter(map(posts, function(v, i)
                -- post listings no longer include "substring"; fall back to "content"
                local text = v.substring or v.content
                if text and #text > #("<p><br></p>") then
                    local href = novelURL .. "/post/" .. v.id

                    return NovelChapter {
                        order = #posts - i,
                        title = v.title,
                        link = href
                    }
                end
            end), function(v) return v end)))
        end

        return info
    end,

    search = function(data)
        if data[QUERY]:match("/user/") then
            return parseListing(filter(creators(), function(v)
                return data[QUERY] == creatorURL(v)
            end))
        end

        local query = data[QUERY]:lower()
        local matches = {}
        for _,v in ipairs(creators()) do
            if v.name:lower():find(query, 1, true) then
                matches[#matches+1] = v
            end
        end
        return parseListing(pageOf(matches, data[PAGE]))
    end,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}
