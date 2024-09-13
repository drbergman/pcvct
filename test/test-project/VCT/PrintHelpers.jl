function printBetweenHashes(s::String)
    if length(s) < 30
        s = lpad(s, length(s) + Int(ceil((40 - length(s))/2)))
        s = rpad(s, 40)
        return [s]
    else
        s_split = split(s)
        s_length = length(s)
        s_lengths = [length(x) for x in s_split]
        sub_lengths = cumsum(s_lengths .+ (0:(length(s_split)-1))) # length of string after combining through the ith token, joining with spaces
        I = findlast(2 .* sub_lengths .< s_length)
        if isnothing(I)
            # then the first token is too long
            s_split = [s_split[1][1:15]; s_split[1][16:end]; s_split[2:end]] # force the split 15 chars into the first token
            I = 1
        end
        
        S1 = join(s_split[1:I], " ") |> printBetweenHashes
        S2 = join(s_split[I+1:end], " ") |> printBetweenHashes
        return [S1; S2]
    end
end

function hashBorderPrint(s::String)
    S = printBetweenHashes(s)
    str = "############################################\n"
    for s in S
        str *= "##" * s * "##\n"
    end
    str *= "############################################"
    println(str)
end