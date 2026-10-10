-- {"id":93278,"ver":"1.1.1","libVer":"1.0.0","author":"TechnoJo4","dep":["url>=1.0.0","dkjson>=1.0.0"]}

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

local function creators()
    if not _creators then
        _creators = jsonGET(apiURL .. "/creators")
    end
    return _creators
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
    chapterType = ChapterType.HTML,

    listings = {
        Listing("All", false, function(data)
            return parseListing(creators())
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
        local creator
        for _,v in pairs(creators()) do
            if novelURL == creatorURL(v) then
                creator = v
            end
        end

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

        return parseListing(filter(creators(), function(v)
            return v.name:match(data[QUERY])
        end))
    end,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}
