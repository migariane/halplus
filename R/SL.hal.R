#' Highly Adaptive Lasso
#'
#' SuperLearner wrapper
#' @param Y outcome
#' @param X data
#' @importFrom glmnet cv.glmnet
#' @export
SL.hal <- function(Y, X, newX, family=gaussian(),
                   verbose=TRUE,
                   obsWeights=rep(1,length(Y)),
                   sparseMat=TRUE,
                   nfolds = ifelse(length(Y)<=100, 20, 10),
                   nlambda = 100, useMin = TRUE,...){
  d <- ncol(X)
  if(!sparseMat){
    uniList <- alply(as.matrix(X),2,function(x){
      # myX <- matrix(x,ncol=length(unique(x)), nrow=length(x)) -
      #   matrix(unique(x), ncol=length(unique(x)), nrow=length(x), byrow=TRUE)
      myX <- matrix(x,ncol=length(x), nrow=length(x)) -
        matrix(x, ncol=length(x), nrow=length(x), byrow=TRUE)
      myX <- ifelse(myX < 0, 0, 1)
      myX
    })

    if(d >=2){
      highDList <- alply(matrix(2:d),1,function(k){
        thisList <- alply(combn(d,k),2,function(x){
          Reduce("*",uniList[x])
        })
        Reduce("cbind",thisList)
      })
      initX <- cbind(Reduce("cbind",uniList), Reduce("cbind",highDList))
      dup <- duplicated(t(initX))
      designX <- initX[,!dup]
    }else{
      initX <- Reduce("cbind",uniList)
      dup <- duplicated(t(initX))
      designX <- initX[,!dup]
    }

    fitCV <- glmnet::cv.glmnet(x = designX, y = Y, weights = obsWeights,
                               lambda.min.ratio=0.001,
                               lambda = NULL, type.measure = "deviance", nfolds = nfolds,
                               family = family$family, alpha = 1, nlambda = nlambda)


    ## get predictions back
    mynewX <- matrix(newX[,1],ncol=length(X[,1]), nrow=length(newX[,1])) -
      matrix(X[,1], ncol=length(X[,1]), nrow=length(newX[,1]), byrow=TRUE)
    mynewX <- ifelse(mynewX < 0, 0, 1)

    makeNewDesignX <- TRUE
    if(all(dim(X)==dim(newX)))
      makeNewDesignX <- !all(X==newX)

    if(makeNewDesignX){
      uniList <- alply(matrix(1:ncol(X)),1,function(x){
        myX <- matrix(newX[,x],ncol=length(X[,x]), nrow=length(newX[,x])) -
          matrix(X[,x], ncol=length(X[,x]), nrow=length(newX[,x]), byrow=TRUE)
        myX <- ifelse(myX < 0, 0, 1)
        myX
      })

      if(d >=2){
        highDList <- alply(matrix(2:d),1,function(k){
          thisList <- alply(combn(d,k),2,function(x){
            Reduce("*",uniList[x])
          })
          Reduce("cbind",thisList)
        })

        initX <- cbind(Reduce("cbind",uniList), Reduce("cbind",highDList))
        designNewX <- initX[,!dup]
      }else{
        initX <- Reduce("cbind",uniList)
        designNewX <- initX[,!dup]
      }
    }else{
      designNewX <- designX
    }

    pred <- predict(fitCV$glmnet.fit, newx = designNewX,
                    s = ifelse(useMin,fitCV$lambda.min, fitCV$lambda.1se), type = "response")
    fit <- list(object = fitCV, useMin = useMin, X=X, dup=dup, sparseMat=sparseMat)
  }else{

    if(is.vector(X)) X <- matrix(X, ncol=1)
    if(is.vector(newX)) newX <- matrix(newX, ncol=1)
    n <- length(X[,1])
    d <- ncol(X)

    if(verbose) cat("Making sparse matrix \n")
    X.init <- makeSparseMat(X=X,newX=X,verbose=TRUE)

    ## find duplicated columns
    if(verbose) cat("Finding duplicate columns \n")
    # Number of columns will become the new number of observations in the data.table
    nIndCols <- ncol(X.init)
    # Pre-allocate a data.table with one column, each row will store a single column from X.init
    datDT <- data.table(ID = 1:nIndCols, bit_to_int_to_str = rep.int("0", nIndCols))
    # Each column in X.init will be represented by a unique vector of integers.
    # Each indicator column in X.init will be converted to a row of integers or a string of cat'ed integers in data.table
    # The number of integers needed to represent a single column is determined automatically by package "bit" and it depends on nrow(X.init)
    nbits <- nrow(X.init) # number of bits (0/1) used by each column in X.init
    bitvals <- bit(length = nbits) # initial allocation (all 0/FALSE)
    nints_used <- length(unclass(bitvals)) # number of integers needed to represent each column
    # For loop over columns of X.init
    ID_withNA <- NULL # track which results gave NA in one of the integers
    for (i in 1:nIndCols) {
      bitvals <- bit(length = nbits) # initial allocation (all 0/FALSE)
      Fidx_base0 <- (X.init@p[i]) : (X.init@p[i + 1]-1) # zero-base indices of indices of non-zero rows for column i=1
      nonzero_rows <- X.init@i[Fidx_base0 + 1] + 1 # actual row numbers of non-zero elements in column i=1
      # print(i); print(nonzero_rows)
      # X.init@i[i:X.init@p[i]]+1 # row numbers of non-zero elements in first col
      bitvals[nonzero_rows] <- TRUE
      # str(bitwhich(bitvals))
      intval <- unclass(bitvals) # integer representation of the bit vector
      # stringval <- str_c(intval, collapse = "")
      if (any(is.na(intval))) ID_withNA <- c(ID_withNA, i)
      set(datDT, i, 2L, value = str_c(str_replace_na(intval), collapse = ""))
    }
    # create a hash-key on the string representation of the column,
    # sorts it by bit_to_int_to_str using radix sort:
    setkey(datDT, bit_to_int_to_str)
    # add logical column indicating duplicates,
    # following the first non-duplicate element
    datDT[, duplicates := duplicated(datDT)]
    # just get the column IDs and duplicate indicators:
    datDT[, .(ID, duplicates)]

    dupInds <- datDT[,ID][which(datDT[,duplicates])]
    uniqDup <- unique(datDT[duplicates==TRUE,bit_to_int_to_str])

    colDups <- alply(uniqDup, 1, function(l){
      datDT[,ID][which(datDT[,bit_to_int_to_str] == l)]
    })

    if(verbose) cat("Fitting lasso \n")
    if(length(dupInds)>0){
      notDupInds <- (1:ncol(X.init))[-unlist(colDups, use.names = FALSE)]
      keepDupInds <- unlist(lapply(colDups, function(x){ x[[1]] }), use.names=FALSE)

      fitCV <- glmnet::cv.glmnet(x = X.init[,c(keepDupInds,notDupInds)], y = Y, weights = obsWeights,
                                 lambda = NULL, lambda.min.ratio=0.001, type.measure = "deviance", nfolds = nfolds,
                                 family = family$family, alpha = 1, nlambda = nlambda)
    }else{
      fitCV <- glmnet::cv.glmnet(x = X.init, y = Y, weights = obsWeights,
                                 lambda = NULL, lambda.min.ratio=0.001, type.measure = "deviance", nfolds = nfolds,
                                 family = family$family, alpha = 1, nlambda = nlambda)
    }

    fit <- list(object = fitCV, useMin = useMin, X=X, dupInds = dupInds, colDups=colDups, sparseMat=sparseMat)
    class(fit) <- "SL.hal"

    if(identical(X,newX)){
      if(length(dupInds) > 0){
        pred <- predict(fitCV, newx = X.init[,c(keepDupInds,notDupInds)], s = ifelse(useMin, fitCV$lambda.min, fitCV$lambda.1se),
                        type = "response")
      }else{
        pred <- predict(fitCV, newx = X.init, s = ifelse(useMin, fitCV$lambda.min, fitCV$lambda.1se),
                        type = "response")
      }
    }else{
      pred <- predict(fit, newdata=newX, bigDesign=FALSE, chunks=10000)
    }
  }

  out <- list(pred = pred, fit = fit)
  cat("Done with SL.hal")
  return(out)
}