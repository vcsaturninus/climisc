#!/usr/bin/lua5.4

--[[
    A cli tool that can be conveniently used in pipelins. It takes a list of values from 
    stdin and it can perform a range of calculations on either all of them or a subset of them,
    or sum them all up. When performing a calculation on each of them, the output of one `calc.lua`
    invocation can be directly fed into the stdin of another instance for further processing.
    The types of of calculations that are allowed are as summarized in the help message but essentially 
    any valid lua mathematical expression is allowed. A few variables are made available that of relevance:
     * i : the current item, when performing a calculation on each item with --foreach
     * s and c: sum and count of items that have been summed up, respectively: these are available
       when using --add and --compute.

--]]


local moopt_path = "/home/vcsaturninus/common/repos/others/moopt/src"
package.path = package.path .. ";" .. moopt_path .. "/?.lua;"

local moopt = require("moopt")

----------------------
local separator
local items = {}

-- mathematical expression to compute either for each item or on the summation result
local expr      
-- available modes of operation
-- ----------------------
local FOREACH_MODE = false
local SUMMATION_MODE = false
-- ----------------------
local RANGE_RESTRICT = false
local range_start 
local range_end
local leftovers = {}
local QUIET = false
----------------------

--------------------------------------------------------------------------------

function help()
    print(string.format([[
%s

Calculate the average of a set of values provided via stdin. The values must be integers
and separated via SEPARATOR. Multiple such lines may be provided.

  -h|--help                   Show this help message and exit
  -s|--separator SEPARATOR    use SEPARATOR as fields separator (else assume whitespace)
  -r|--range                  The range of values to compute. The syntax is "start,end",
                              with the first value inclusive and the second exclusive 
                              i.e. [start,end)). You can specify both or either but must 
                              specify at least one. For example, "3," means all values starting
                              with the 3rd one. Converesely, ",77" means all values up until but
                              not including the 77th one. Of course, "11-16" means values 11, 12, 13,
                              14, and 15 (but not 16).
   -a|--add                   Sum up all items pased in via stdin.
   -c|--compute               An additional computation step to be carried out on the summation. This must be
                              a valid lua mathematical expression expressed in terms of either or both of
                              s (sum) and c (count of items that were summed up). For example
                              "s / (256*c)". If c=40 and sum wound up being 270, you get '270 / (256 * 40).'
   --foreach EXP              Carry out a certain computation for each item then print the result to stdout.
                              If this is used, then --compute and --sum cannot be used. EXP must be a mathematical
                              expression to be evaluated by Lua expressed in terms of i. i will be replaced by 
                              each item, as if in a loop.
]], arg[0]))
end

-- split string on separator SEP and return
-- table of values
function split(s, sep)
    assert(s)
    local sep = sep or "%s" -- whitespace is default
    --print(string.format("proceeding with string %s and sep %s", s, sep))
    
    local res = {}

    for x in s:gmatch(string.format("[^%s]+", sep)) do
        --print(x)
        table.insert(res, x)
    end

    return res
end

-- sum up all values in t and return the result.
-- The values in t must be integers.
function sum_all(t)
    assert(t)
    local num=0
    local count = #t

    if not QUIET then
        print(string.format("[ ] Will find the average of %s items.", count))
        print("0")
    end

    -- compute average
    for k,v in pairs(t) do
        if not QUIET then
            print("+ " .. v)
        end
        num = num+v
    end

    print(string.format("| => %s", num))
    return num
end

----------------------------------------------------------
if #arg < 1 then
    print("missing arguments")
    help()
    os.exit(3)
end

local optstring = "+ac:hs:r:q"
local longopts = {
    add = {val="a", has_arg=0},
    foreach = {val="foreach", has_arg=1},
    compute = {val="c", has_arg=1},
    help = {val="h", has_arg=0},
    separator = {val="s", has_arg=1},
    range = {val="r", has_arg=1},
    quiet = {val="q", has_arg=0}
}


for opt,optind,optarg,optopt in moopt.getopt_long(arg, leftovers,optstring,longopts) do
    if opt == "h" then
        help()
        os.exit()
    
    elseif opt == "a" then
        SUMMATION_MODE=true
        if FOREACH_MODE then
            print("-a|--add  and --foreach are mutually exclusive!")
            os.exit(11)
        end

    elseif opt == "c" then
        expr = optarg
        if not SUMMATION_MODE then
            print("-c|--compute can only be used in summation mode (i.e. with -a|--add)")
            os.exit(11)
        end

    elseif opt == "foreach" then
        FOREACH_MODE=true
        QUIET=true  -- quiet mode must be set so that only the values themselves get printed,
                    -- making the output suitable for pipelines
        expr = optarg
        if SUMMATION_MODE then
            print("-a|--add  and --foreach are mutually exclusive!")
            os.exit(11)
        end
        
    elseif opt == "s" then
        separator = optarg

    elseif opt == "r" then
        local range = optarg 
        range = split(range, ",") 
        range_start, range_end = table.unpack(range)
        range_start = tonumber(range_start)
        range_end = tonumber(range_end)

        if optarg:sub(1,1) == "," then -- no start range
            range_end = range_start
            range_start = nil
        end

    elseif opt == "q" then
        QUIET = true
    elseif opt == ":" or opt == "?" then
        os.exit(17)
    end
end


if #leftovers > 0 then
    print("Superfluous/misunderstood cl args:", table.unpack(leftovers))
end

--------------------------------------------------------
-- parse each line read from stdin
for line in io.stdin:lines() do
    --print("line = " .. line)
    for _,v in ipairs(split(line, separator)) do
        table.insert(items, v)
    end
end

-- adjust range as needed
if range_end and range_end > #items+1 then
    print(string.format("[ ] range_end (%s) past the end of the allowable range (%s). Reducing to %s", 
        range_end, #items+1, #items+1)
        )
    range_end = #items+1
end

if range_start then
    assert(range_start <= #items, 
        string.format("start range index (%s) > the count of items provided (%s)!", range_start, #items)
        )
end

if range_start and range_end then
    local range_restricted = {}
    for i=range_start,range_end-1 do
        table.insert(range_restricted, items[i])
    end

    items= range_restricted

elseif range_start or range_end then
    local range_restricted = {}
    for i=range_start or 1, (range_end and range_end-1) or #items do
        table.insert(range_restricted, items[i])
    end

    items = range_restricted
end
---------------------------------------------

local result

if SUMMATION_MODE then
    local s = sum_all(items)

    if expr then 
        local saved_expression = expr
        -- substitute s with the sum calculated and c with the count of items summed up
        local expr = expr:gsub("s", s)
        expr = expr:gsub("c", #items)

        if not QUIET then
            print(string.format("Converting expression '%s' => '%s'", saved_expression, expr))
        end

        result,msg  = load(string.format("return %s", expr))
        if msg then 
            error(msg)
        else
            result = result()
        end
    end

    -- extra computation, not just sum
    if result then print(string.format("| => %s", result)) end

elseif FOREACH_MODE then
    for _, item in ipairs(items) do
        --print("expression was " .. expr)
        expression = expr:gsub("i", item)
        --print("expression was " .. expression)
        result, msg = load(string.format("return %s", expression))

        if msg then 
            error(msg)
        else
            result = result()
        end

        print(result)
    end
end
