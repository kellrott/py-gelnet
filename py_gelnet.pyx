
cimport gelnet

from cpython cimport bool
cimport numpy as np
import numpy as np

class GelnetRegression:
    def __init__(self, l1, l2, L, max_iter=100):
        self.l1 = l1
        self.l2 = l2
        self.L = L
        self.max_iter = max_iter
        self.coef_ = None
        self.intercept_ = None

    def fit(self, X, y):
        model = gelnet(np.asfortranarray(X), y, self.l1, self.l2, P=self.L, max_iter=self.max_iter)
        self.coef_ = model[0]
        self.intercept_ = model[1]

    def predict(self, X):
        return X.dot(self.coef_) + self.intercept_

def adj2lapl(A):
    if A.shape[0] != A.shape[1]:
        raise Exception("Need NxN matrix")
    L = -A
    np.fill_diagonal(L, np.zeros(L.shape[0]))
    s = np.apply_along_axis(sum, 0, L)
    np.fill_diagonal(L, -s)
    return L.copy(order="F")


def adj2nlapl(A):
    if A.shape[0] != A.shape[1]:
        raise Exception("Need NxN matrix")
    old = np.seterr(divide="ignore")
    A = A.astype(float)
    np.fill_diagonal(A, np.zeros(A.shape[0]))
    d = np.apply_along_axis(sum, 0, A)
    d = np.sqrt(np.divide(1,d))
    d[np.isinf(d)]=0.0
    np.seterr(**old)
    L = adj2lapl(A)
    res = (L * d).transpose() * d
    return res.copy(order="F")


def gelnet(X, y, l1, l2, a=None, d=None, nFeats=None, P=None,
            max_iter=100, eps=1e-5, b_init=None,
            fix_bias=False, silent=False, balanced=False, nonneg=False ):

    X = np.asarray(X)
    if y is not None:
        y = np.asarray(y)

    n = X.shape[0]
    p = X.shape[1]

    w_init = np.zeros(p)
    m = np.zeros(p)
    if d is None:
        d = np.ones(p)
    if a is None:
        a = np.ones(n)

    if P is None:
      P = np.diag(np.ones(p)).copy(order="F")
    else:
      P = np.asarray(P)

    if not X.flags.f_contiguous:
        X = X.copy(order="F")

    if y is None:
        f_gel = lambda L1: gelnet_oneclass( X=X, l1=L1, l2=l2,
            d=d, P=P, m=m, max_iter=max_iter, eps=eps, w_init=w_init,
            silent=silent, nonneg=nonneg )
    else:
        f_gel = lambda L1: gelnet_lin( X=X, y=y, l1=L1, l2=l2, a=a,
            d=d, P=P, m=m, max_iter=max_iter, eps=eps, w_init=w_init,
            b_init=b_init, fix_bias=fix_bias, silent=silent, nonneg=nonneg )


    return f_gel(l1)

    """
    w_init=rep(0,p),
    a=rep(1,n), d=rep(1,p), P=diag(p), m=rep(0,p)
    """

"""

  {
    n <- nrow(X)
    p <- ncol(X)

    ## Determine the problem type
    if( is.null(y) )
      {
        if( !silent ) cat( "Training a one-class model\n" )
        f.gel <- function(L1) {gelnet.oneclass( X, L1, l2, d, P, m, max.iter, eps, w.init, silent, nonneg )}
      }
    else if( is.factor(y) )
      {
        if( nlevels(y) == 1 )
          stop( "All labels are identical\nConsider training a one-class model instead" )
        if( nlevels(y) > 2 )
          stop( "Labels belong to a multiclass task\nConsider training a set of one-vs-one or one-vs-rest models" )
        if( !silent ) cat( "Training a logistic regression model\n" )
        if( is.null(b.init) ) b.init <- 0
        f.gel <- function(L1) {gelnet.logreg( X, y, L1, l2, d, P, m, max.iter, eps, w.init, b.init, silent, balanced, nonneg )}
      }
    else if( is.numeric(y) )
      {
        if( !silent ) cat( "Training a linear regression model\n" )
        if( is.null(b.init) ) b.init <- sum(a*y) / sum(a)
        f.gel <- function(L1) {gelnet.lin( X, y, L1, l2, a, d, P, m, max.iter, eps, w.init, b.init, fix.bias, silent, nonneg )}
      }
    else
      { stop( "Unknown label type\ny must be a numeric vector, a 2-level factor or NULL" ) }

    ## Train a model with the required number of features (if requested)
    if( !is.null(nFeats) )
      {
        L1s <- L1.ceiling( X, y, a, d, P, m, l2, balanced )
        return( gelnet.L1bin( f.gel, nFeats, L1s ) )
      }
    else
      { return( f.gel(l1) ) }
  }
"""


def gelnet_lin(np.ndarray[double, ndim=2, mode="fortran"] X,
        np.ndarray[double, ndim=1, mode="c"] y,
        double l1, double l2,
        np.ndarray[double, ndim=1, mode="c"] a=None,
        np.ndarray[double, ndim=1, mode="c"] d=None,
        np.ndarray[double, ndim=2, mode="fortran"] P=None,
        np.ndarray[double, ndim=1, mode="c"] m=None,
        int max_iter = 100, double eps = 1e-5,
        np.ndarray[double, ndim=1, mode="c"] w_init = None,
        b_init = None,
        fix_bias=False, bool silent=False, bool nonneg=False ):

    """
    a = rep(1,n), d = rep(1,p), P = diag(p),
    m=rep(0,p)
    b.init = sum(a*y)/sum(a),
    w.init = rep(0,p),
    """

    cdef int n = X.shape[0]
    cdef int p = X.shape[1]

    if a is None:
        a = np.ones(n)
    if d is None:
        d = np.ones(p)
    if P is None:
        raise Exception("Do something here")
    if m is None:
        m = np.zeros(p)
    if w_init is None:
        w_init = np.zeros(p)
    cdef double b_init_double = 0.0
    if b_init is None:
        b_init_double = np.sum(a*y) / np.sum(a)
    else:
        b_init_double = b_init

    if y.shape[0] != n:
        raise Exception("len(y) != n")
    if a.shape[0] != n:
        raise Exception("len(a) != n")
    if d.shape[0] != p:
        raise Exception("len(d) != p")
    if P.shape[0] != p or P.shape[1] != p:
        raise Exception("dim(P) != p,p")
    if m.shape[0] != p:
        raise Exception("len(m) != p")
    if w_init.shape[0] != p:
        raise Exception("len(w_init) != p")

    cdef int nonneg_int = 0
    if nonneg:
        nonneg_int = 1
    cdef int silent_int = 0
    if silent:
        silent_int = 1
    cdef int fix_bias_int = 0
    if fix_bias:
        fix_bias_int = 1
    cdef np.ndarray[double, ndim=1, mode="c"] S = X.dot(w_init) + b_init_double
    cdef np.ndarray[double, ndim=1, mode="c"] Pw = P.dot(w_init - m)
    #cdef np.ndarray[double, ndim=2, mode="f"] X_trans = X.transpose().copy(order="C")

    gelnet.gelnet_lin_opt(<double *> X.data, <double *>y.data,
        <double *>a.data, <double *>d.data, <double *>P.data, <double *>m.data, &l1, &l2,
        <double *>S.data,
        <double *>Pw.data, &n, &p, &max_iter, &eps, &fix_bias_int, <double *>w_init.data,
        &b_init_double, &silent_int, &nonneg_int
    )

    return w_init, b_init_double


"""
gelnet.lin <- function( X, y, l1, l2, a = rep(1,n), d = rep(1,p), P = diag(p),
                       m=rep(0,p), max.iter = 100, eps = 1e-5, w.init = rep(0,p),
                       b.init = sum(a*y)/sum(a), fix.bias=FALSE, silent=FALSE, nonneg=FALSE )

  {
    n <- nrow(X)
    p <- ncol(X)

    ## Verify argument dimensionality
    stopifnot( length(y) == n )
    stopifnot( length(a) == n )
    stopifnot( length(d) == p )
    stopifnot( all( dim(P) == c(p,p) ) )
    stopifnot( length(m) == p )
    stopifnot( length(w.init) == p )
    stopifnot( length(b.init) == 1 )
    stopifnot( length(l1) == 1 )
    stopifnot( length(l2) == 1 )

    ## Verify name matching (if applicable)
    if( is.null(colnames(X)) == FALSE && is.null(colnames(P)) == FALSE )
      {
        stopifnot( is.null( rownames(P) ) == FALSE )
        stopifnot( all( colnames(X) == rownames(P) ) )
        stopifnot( all( colnames(X) == colnames(P) ) )
      }

    ## Set the initial parameter estimates
    S <- X %*% w.init + b.init
    Pw <- P %*% (w.init - m)

    ## Call the C routine
    res <- .C( "gelnet_lin_opt",
              as.double(X), as.double(y), as.double(a), as.double(d),
              as.double(P), as.double(m), as.double(l1), as.double(l2),
              as.double(S), as.double(Pw), as.integer(n), as.integer(p),
              as.integer(max.iter), as.double(eps), as.integer(fix.bias),
              w = as.double( w.init ), b = as.double(b.init), as.integer(silent), as.integer(nonneg) )

    res <- res[c("w","b")]
    names( res$w ) <- colnames(X)

    res
  }
"""

def gelnet_oneclass_obj(np.ndarray[double, ndim=1, mode="c"] w,
        np.ndarray[double, ndim=2, mode="fortran"] X,
        double l1, double l2,
        np.ndarray[double, ndim=1, mode="c"] d,
        np.ndarray[double, ndim=2, mode="fortran"] P,
        np.ndarray[double, ndim=1, mode="c"] m):
    s = np.matmul(X, w)
    LL = np.mean( s - np.log( 1 + np.exp(s) ) )
    R1 = l1 * np.matmul(d.T, np.abs(w))
    R2 = l2 * np.matmul((w-m).T, np.matmul(P, (w-m).T)) / 2
    return R1 + R2 - LL

def gelnet_oneclass(np.ndarray[double, ndim=2, mode="fortran"] X,
        double l1, double l2,
        np.ndarray[double, ndim=1, mode="c"] d=None,
        np.ndarray[double, ndim=2, mode="fortran"] P=None,
        np.ndarray[double, ndim=1, mode="c"] m=None,
        int max_iter = 100, double eps = 1e-5,
        np.ndarray[double, ndim=1, mode="c"] w_init = None,
        bool silent=False, bool nonneg=False ):

    cdef int n = X.shape[0]
    cdef int p = X.shape[1]

    if d is None:
        d = np.ones(p)
    if w_init is None:
        w_init = np.zeros(p)

    w = w_init

    fprev = gelnet_oneclass_obj(w=w, X=X, l1=l1, l2=l2, d=d, P=P, m=m)
    for iter in range(1, max_iter):
        if not silent:
            print("Iteration %s : f = %s" % (iter, fprev))
        ## Compute the current fit
        s = np.matmul(X, w)
        pr = 1 / (1 + np.exp(-s))

        ## Compute the sample weights and active response
        a = pr * (1-pr)
        z = s + 1/pr

        ## Run coordinate descent for the resulting regression problem
        w, b = gelnet_lin( X=X, y=z, l1=l1, l2=l2,
            a=a, d=d, P=P, m=m, max_iter=iter*2,
            eps=eps, w_init=w, b_init=0, fix_bias=True, silent=True, nonneg=nonneg )
        f = gelnet_oneclass_obj(w=w, X=X, l1=l1, l2=l2, d=d, P=P, m=m)
        if ( np.abs(f - fprev) / np.abs(fprev) < eps ):
            break
        else:
            fprev = f

    return w, 0.0
