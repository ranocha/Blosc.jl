module Blosc
export compress, compress!, decompress, compress!

const libblosc = Pkg.dir("Blosc", "deps", "libblosc")

__init__() = ccall((:blosc_init,libblosc), Void, ())

# the following constants should match those in blosc.h
const MAX_OVERHEAD = 16

# returns size of compressed data inside dest
function compress!{T}(dest::Vector{Uint8}, src::Array{T};
	              level::Integer=6, shuffle::Bool=true,
                      typesize::Integer=sizeof(T))	
    # See Blosc/c-blosc#67 -- they use an int for the compressed size
    sz = ccall((:blosc_compress,libblosc), Cint,
               (Cint,Cint,Csize_t, Csize_t, Ptr{T}, Ptr{Uint8}, Csize_t),
               level, shuffle, typesize, sizeof(src), src, dest, sizeof(dest))
    sz < 0 && error("Blosc error $sz")
    return convert(Int, sz)
end

function compress{T}(src::Array{T};
                     level::Integer=6, shuffle::Bool=true,
                     typesize::Integer=sizeof(T))
    dest = Array(Uint8, div(sizeof(src), 4) + MAX_OVERHEAD)
    while true
        sz = compress!(dest,src; level=level,shuffle=shuffle,typesize=typesize)
        if sz > 0
            return resize!(dest, sz)
        else
            resize!(dest, max(sizeof(src) + MAX_OVERHEAD,
                              div(sizeof(dest) * 3, 2)))
        end
    end
end

# given a compressed buffer, return the (uncompressed, compressed, block) size
const sizes_vals = Array(Csize_t, 3)
function sizes(buf::Vector{Uint8})
    ccall((:blosc_cbuffer_sizes,libblosc), Void,
          (Ptr{Uint8}, Ptr{Csize_t}, Ptr{Csize_t}, Ptr{Csize_t}),
          buf,
          pointer(sizes_vals, 1),
          pointer(sizes_vals, 2),
          pointer(sizes_vals, 3))
    return (sizes_vals[1], sizes_vals[2], sizes_vals[3])
end

function decompress!{T}(dest::Vector{T}, src::Vector{Uint8})
    uncompressed, = sizes(src)
    sizeT = sizeof(T)
    len = div(uncompressed, sizeT)
    if len*sizeT != uncompressed
        error("uncompressed data is not a multiple of sizeof($T)")
    end
    resize!(dest, len)
    sz = ccall((:blosc_decompress,libblosc), Cint, (Ptr{Uint8},Ptr{T},Csize_t),
               src, dest, sizeof(dest))
    sz <= 0 && error("Blosc decompress error $sz")
    return dest
end

decompress{T}(::Type{T}, src::Vector{Uint8}) = decompress!(Array(T,0), src)

set_num_threads(n::Integer) = ccall((:blosc_set_nthreads,libblosc),
                                    Cint, (Cint,), n)

compressors() = split(bytestring(ccall((:blosc_list_compressors,libblosc),
                                       Ptr{Uint8}, ())),
                      ",")

function set_compressor(s::String)
    compcode = ccall((:blosc_set_compressor,libblosc), Cint, (Ptr{Uint8},), s)
    compcode == -1 && throw(ArgumentError("unrecognized compressor $s"))
    return compcode
end

end # module