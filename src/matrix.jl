## matrix class stuff
## XXX work with Array{Sym}, not python array objects
## requires conversion from SymMatrix -> Array{Sym} in outputs, as appropriate

immutable SymMatrix <: SymbolicObject
    x::PyCall.PyObject
end

## convert SymPy matrices to SymMatrix
matrixtype = sympy.matrices["MatrixBase"]
pytype_mapping(matrixtype, SymMatrix)
convert(::Type{SymMatrix}, o::PyCall.PyObject) = SymMatrix(o)



## map for linear indexing. Should be a function in base, but don't know it
function find_ijk(i, s)
    out = Integer[]
    while length(s) > 1
        p = prod(s[1:end-1])
        push!(out, iceil(i/p))
        i = (i-1) % prod(s[1:end-1]) +1
        s = s[1:end-1]
    end
        
    push!(out, i)
    tuple((reverse!(out) - 1)...)
end


## no linear indexing of matrices allowed here
getindex(s::SymMatrix, i::Integer...) = pyeval("x[i]", x=s.x, i= tuple(([i...]-1)...))
getindex(s::SymMatrix, i::Symbol) = project(s)[i] # is_nilpotent, ... many such predicates
getindex(s::Array{Sym}, i::Symbol) = project(s)[i] # digaonalize..

## we want our matrices to be arrays of Sym objects, not symbolic matrices
## so that julia manages them
## it is convenient (for printing, say) to convert to a sympy matrix
convert(SymMatrix, a::Array{Sym}) = Sym(sympy.Matrix(map(project, a)))
function convert(::Type{Array{Sym}}, a::SymMatrix)
    sz = size(a)
    ndims = length(sz)
    if ndims == 0
        a
    elseif ndims == 1
        Sym[a[i] for i in 1:length(a)]
    elseif ndims == 2
        Sym[a[i,j] for i in 1:size(a)[1], j in 1:size(a)[2]]
    else
        ## need something else for arrays... XXX -- can't linear index a
        b = Sym[a[find_ijk(i, sz)] for i in 1:length(a)]
        reshape(b, sz)
    end
end
  
## when projecting, we convert to a symbolic matrix thne project  
project(x::Array{Sym}) = convert(SymMatrix, x) |> project


## linear algebra functions that are methods of sympy.Matrix
## return a "scalar"
#for (nm, meth) in ((:det, "det"), )
for meth in (:det,
           :trace,
           :condition_number,
           :has,
           :is_anti_symmetric, :is_diagonal, :is_diagonalizable,:is_nilpotent, 
           :is_symbolic, :is_symmetric, 
           :norm,
           :trace
           )

    cmd = "x." * string(meth) * "()"
    @eval ($meth)(a::SymMatrix) = Sym(pyeval(($cmd), x=project(a)))
    @eval ($meth)(a::Array{Sym, 2}) = ($meth)(convert(SymMatrix, a))
    eval(Expr(:export, meth))
end



## methods called as properties
matrix_operators = (:H, :C,  
                    :is_lower, :is_lower_hessenberg, :is_square, :is_upper,  :is_upper_hessenberg, :is_zero
)

for meth in matrix_operators
     meth_name = string(meth)
     @eval ($meth)(ex::SymMatrix, args...; kwargs...) = ex[symbol($meth_name)]
     @eval ($meth)(ex::Array{Sym}, args...; kwargs...) = ex[symbol($meth_name)]
    eval(Expr(:export, meth))
end



## These take a matrix, return a container of symmatrices. Here we convert these to arrays of sym
map_matrix_methods = (:LDLsolve,
                      :LDLdecomposition, :LDLdecompositionFF,
                      :LUdecomposition_Simple,
                      :LUsolve,
                      :QRdecomposition, :QRsolve,
                      :adjoint, :adjugate,
                      :cholesky, :cholesky_solve, :cofactor, :conjugate, 
                      :cross, 
                      :diagaonal_solve, :diagonalize, :diff, :dot, :dual,
                      :exp, :expand,
                      :integrate, 
                      :inv, :inverse_ADJ, :inverse_GE, :inverse_LU,
                      :jordan_cells, :jordan_form,
                      :limit,
                      :lower_triangular_solve,
                      :minorEntry, :minorMatrix,
                      :n, :normalized, :nullspace,
                      :permuteBkwd, :permuteFwd,
                      :print_nonzero,
                      :singular_values,
                      :transpose,
                      :upper_triangular_solve,
                      :vec, :vech
                      )

for meth in map_matrix_methods
    meth_name = string(meth)
    @eval ($meth)(ex::SymMatrix, args...; kwargs...) = call_matrix_meth(ex, symbol($meth_name), args...; kwargs...)
    @eval ($meth)(ex::Array{Sym}, args...; kwargs...) = call_matrix_meth(convert(SymMatrix, ex), symbol($meth_name), args...; kwargs...)
    eval(Expr(:export, meth))
end


### Some special functions

Base.conj(a::SymMatrix) = conjugate(a)

## :eigenvals, returns {val => mult, val=> mult} ## eigvals
function eigvals(a::Array{Sym,2})
    d = convert(SymMatrix, a)[:eigenvals]()
    out = Sym[]
    for (k, v) in d
        for i in 1:v
            push!(out, Sym(k))
        end
    end
    out
end

## eigenvects ## returns list of triples (eigenval, multiplicity, basis).
function eigvecs(a::Array{Sym,2})
    d = convert(SymMatrix, a)[:eigenvects]()
    [{:eigenvalue=>Sym(u[1]), :multiplicity=>u[2], :basis=>map(x -> Sym(x), u[3])} for u in d]
end
    

function rref(a::Array{Sym, 2}; kwargs...)
    d = convert(SymMatrix, a)[:rref](; kwargs...)
    convert(Array{Sym}, convert(Sym, d[1]))
end

## call with a (A,b), return array
for fn in (:cross,
           :LUSolve, 
           :dot)
    cmd = "x." * string(fn) * "()"
    @eval ($fn)(A::SymMatrix, b::Sym) = convert(Array{Sym}, pyeval(($cmd), A=project(A), b=project(b)))
    @eval ($fn)(A::Array{Sym, 2}, b::Vector{Sym}) = $(fn)(convert(SymMatrix,A), convert(SymMatrix, b))
end

## GramSchmidt -- how to call?
## call with a (A,b), return scalar
# for fn in ()
#     @eval ($fn)(A::Sym, b::Sym) = convert(Array{Sym}, pyeval("A.($fn)(b)", A=project(A), b=project(b)))
#     @eval ($fn)(A::Array{Sym, 2}, b::Vector{Sym}) = ($fn)(convert(SymMatrix, A), convert(SymMatrix, b))
# end
    


# Jacobian
# example:
# rho, phi = @syms rho phi
# M = [rho*cos(phi), rho*sin(phi), rho^2]
# Y = [rho, phi]
# jacobian(M, Y)
function jacobian(x::Array{Sym}, y::Array{Sym})
    X = convert(SymMatrix, x)
    Y = convert(SymMatrix, y)
    call_matrix_meth(X, :jacobian, Y)
end
export jacobian

## x, y = symbols("x y")
## f = x^2 - 2x*y
## hessian(f, [x,y])
function hessian(f::Sym, x::Array{Sym})
    out = sympy_meth(:hessian, f, x)
    convert(SymMatrix, out) |> u -> convert(Array{Sym}, u)
end
export hessian