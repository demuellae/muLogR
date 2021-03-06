########################################################################################################################
## logger.R
## adapted code from the RnBeads package (courtesy of Yassen Assenov)
########################################################################################################################

## G L O B A L S #######################################################################################################

.LOG.INFO <- new.env()

.LOG.INDENT <- "    "
.LOGGER <- "muLogR"
.LOG.STAT <- c("INFO" = "INFO", "STATUS" = "STATUS", "WARNING" = "WARNING", "ERROR" = "ERROR")

## F U N C T I O N S ###################################################################################################

## get.memory.usage
##
## Gets the memory used by this process.
##
## @return Memory, in Gigabytes, used in this R session.
## @details
## In Windows, the returned value measures only the memory allocated by this session. It does not include the memory
## used by the R system itself (and many of the loaded libraries). In Linux and Mac OS, the returned value is the total
## memory used by the R process that runs this script.
## @author adapted by Fabian Mueller from RnBeads code by Yassen Assenov
get.memory.usage <- function() {
	if (.Platform$OS == "windows") {
		memused <- memory.size() / 1024
	} else if (Sys.info()["sysname"] == "Darwin") { # MAC
		processinfo <- system(paste('top -pid', Sys.getpid(), '-l 1 -stats MEM'), intern = TRUE)
		processinfo <- gsub("\\+$", "", processinfo[length(processinfo)])
		regex.process <- "(\\d+)([A-Z]?)$"
		if (grepl(regex.process, processinfo)) {
			memused <- as.double(gsub(regex.process, "\\1", processinfo))
			memscale <- gsub(regex.process, "\\2", processinfo)
			if (memscale == "") {
				memused <- (memused / 1048576) / 1024
			} else if (memscale == "K") {
				memused <- memused / 1048576
			} else if (memscale == "M") {
				memused <- memused / 1024
			} else if (memscale == "T") {
				memused <- memused * 1024
			}
		} else {
			memused <- 0
		}
	} else {
		processinfo <- paste("/proc", Sys.getpid(), "status", sep = "/")
		processinfo <- scan(processinfo, what = character(), sep = "\n", quiet = TRUE)
		memused <- grep("^VmSize\\:(.+)kB", processinfo, value = TRUE)
		memused <- as.double(gsub("\\s+", "", substr(memused, 8, nchar(memused) - 2))) / 1048576
	}
	return(memused)
}

########################################################################################################################

## get.disk.usage
##
## Gets the space used by all files and subdirectories of the given path.
##
## @param path Base directory to scan.
## @return Combined size, in Gigabytes, used by the files in the given path and in its subdirectories. The disk
##         space used by the directory entries themselves is not included.
## @author adapted by Fabian Mueller from RnBeads code by Yassen Assenov
get.disk.usage <- function(path = getOption("fftempdir")) {
	if (!isTRUE(file.info(path)[, "isdir"])) {
		stop("invalid value for path; expected existing directory")
	}
	sum(file.info(dir(path, full.names = TRUE, recursive = TRUE))[, "size"] / 1048576) / 1024
}

########################################################################################################################

format.usage <- function(usage.extractor) {
	tryCatch(format(usage.extractor(), digits = 1L, nsmall = 1L, justify = "right", width = 6),
		error = function(e) { "      " })
}

########################################################################################################################

## logger.format
##
## Memory usage formatter for the text logger.
##
## @param record Log message in the form of a record. This message is expected to start with a status word, e.g. with
##               \code{WARNING}.
## @return       Character containing the formatted message.
logger.format <- function(record) {

	memory.used <- ifelse(.LOG.INFO[["memory"]], paste0(format.usage(get.memory.usage), " "), "")
	disk.used <- ifelse(.LOG.INFO[["disk"]], paste0(format.usage(get.disk.usage), " "), "")

	## Right-align the status word
	status.word <- sub("^([A-Z]+) .+", "\\1", record$msg)
	if (status.word %in% .LOG.STAT) {
		prefix <- paste(rep(" ", max(nchar(.LOG.STAT)) - nchar(status.word)), collapse = "")
	} else {
		prefix <- ""
	}
	## Prepend date, time, memory used and temporary disk space used
	paste0(record$timestamp, " ", memory.used, disk.used, prefix, record$msg)
}

########################################################################################################################

## Transforms a vector of message elements to a character.
##
## @param txt    Character vector with message elements.
## @param indent Flag indicating if the message must be prepended by \code{.LOG.INDENT} to indicate it belongs to
##               a specific section.
## @return       Single-element character vector concatenating all elements in \code{txt}, possibly with indentation.
logger.transform <- function(txt, indent = TRUE) {
	if (!(is.character(txt) && is.vector(txt))) {
		stop("invalid value for parameter txt")
	}
	if (length(txt) > 1) {
		txt <- paste(txt, collapse = " ")
	}
	if (indent && length(.LOG.INFO[["titles"]]) != 0) {
		txt <- paste(paste(rep(.LOG.INDENT, length(.LOG.INFO[["titles"]])), collapse = ""), txt, sep = "")
	}
	return(txt)
}

########################################################################################################################

logger.paste <- function(status.word, txt, logger = .LOGGER) {
	record <- list(
		timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S "),
		msg = paste(.LOG.STAT[status.word], logger.transform(txt)))
	txt <- paste(.LOG.INFO[["formatter"]](record), "\n", sep = "")
	for (fname in .LOG.INFO[["logfiles"]]) {
		cat(txt, file = ifelse(is.na(fname), "", fname), append = TRUE)
	}
}

########################################################################################################################

#' logger.getfiles
#'
#' Gets the files currently used by the logger.
#'
#' @return Vector storing the full names of the files that are being used by the logger. This vector contains \code{NA}
#'         as an element if the logger is (also) using the console for its output. If the logger is not initialized, this function returns \code{NULL}.
#'
#' @examples
#' \donttest{
#' if (NA %in% logger.getfiles())
#'   cat("Console logger is enabled\n")
#' }
#' @seealso \code{\link{logger.isinitialized}} to check if logging is activated;
#'   \code{\link{logger.start}} for initializing a logger or starting a section
#' @author adapted by Fabian Mueller from RnBeads code by Yassen Assenov
#' @export
logger.getfiles <- function() {
	if (exists("logfiles", envir = .LOG.INFO, inherits = FALSE)) {
		return(get("logfiles", envir = .LOG.INFO, inherits = FALSE))
	}
	return(NULL)
}

########################################################################################################################

#' logger.isinitialized
#'
#' Checks if the logger is initialized.
#'
#' @return \code{TRUE} if the logger was initialized and is in use; \code{FALSE} otherwise.
#'
#' @examples
#' \donttest{
#' if (!logger.isinitialized())
#'   logger.start(fname = NA)
#' }
#' @seealso \code{\link{logger.start}} for initializing a logger or starting a section
#' @author adapted by Fabian Mueller from RnBeads code by Yassen Assenov
#' @export
logger.isinitialized <- function() {
	return(exists("logfiles", envir = .LOG.INFO, inherits = FALSE))
}

########################################################################################################################

#' Writing text messages to the log file.
#'
#' Appends a single-line status message to the log text file. The message is prepended by its type, which is one of
#' \code{STATUS}, \code{INFO}, \code{WARNING} or \code{ERROR}.
#'
#' @rdname loggerMessages
#' @aliases logger.status
#' @aliases logger.info
#' @aliases logger.warning
#' @aliases logger.error
#'
#' @param txt       Text to add to the log file. This must be a \code{character} vector; its elements are concatenated
#'                  using a single space (\code{" "}) as a separator.
#' @param terminate Flag indicating if the execution is to be terminated after this error message is added to the log.
#' @return None (invisible \code{NULL}).
#'
#' @examples
#' \donttest{
#' if (!logger.isinitialized())
#'   logger.start(fname = NA)
#' logger.status(c("Reached step", 2))
#' }
#' @seealso \code{\link{logger.isinitialized}}to check if logging is activated;
#'   \code{\link{logger.start}} for initializing a logger or starting a section
#' @author adapted by Fabian Mueller from RnBeads code by Yassen Assenov
#' @export
logger.status <- function(txt) {
	if (!logger.isinitialized()) {
		# stop("logger is not initialized")
		logger.start(fname=NA) #initialize the logger to the console if not started yet
	}
	logger.paste("STATUS", txt)
}

########################################################################################################################

#' @rdname loggerMessages
#' @export
logger.info <- function(txt) {
	if (!logger.isinitialized()) {
		# stop("logger is not initialized")
		logger.start(fname=NA) #initialize the logger to the console if not started yet
	}
	logger.paste("INFO", txt)
}

########################################################################################################################

#' @rdname loggerMessages
#' @export
logger.warning <- function(txt) {
	if (!logger.isinitialized()) {
		# stop("logger is not initialized")
		logger.start(fname=NA) #initialize the logger to the console if not started yet
	}
	logger.paste("WARNING", txt)
}

########################################################################################################################

#' @rdname loggerMessages
#' @export
logger.error <- function(txt, terminate=FALSE) {
	if (!logger.isinitialized()) {
		# stop("logger is not initialized")
		logger.start(fname=NA) #initialize the logger to the console if not started yet
	}
	logger.paste("ERROR", txt)
	if (terminate) {
		for (logfile in get("logfiles", envir = .LOG.INFO, inherits = FALSE)) {
			if (is.na(logfile)) {
				cat("\n")
			} else {
				cat("\n", file = logfile, append = TRUE)
			}
		}
		quit(save="no", status = 1L)
	}
	stop(logger.transform(txt, FALSE))
}

########################################################################################################################

#' Log File Management
#'
#' Functions for logger management.
#'
#' @rdname loggerManagement
#' @aliases logger.start
#' @aliases logger.completed
#' @aliases logger.close
#'
#' @param txt   Description to add to the log file. The words \code{STARTED} and \code{COMPLETED} are prepended to the
#'              message upon initialization and completion of the section, respectively.
#' @param fname Name of the log file and/or console. Note that at most one file name can be specified. The function
#'              \code{logger.start} normalizes the given name, that is, it converts it to an absolute name. If this
#'              parameter is \code{NA}, logger messages are printed to the console. If it is a two-element vector
#'              containing one file name and \code{NA}, the logger is (re)initialized to print messages both to the
#'              given file name and the console. A value of \code{NULL} (default) indicates the logger should continue
#'              using the previously specified file.
#' @return None (invisible \code{NULL}).
#'
#' @examples
#' \donttest{
#' if (!logger.isinitialized())
#'   logger.start(fname = NA)
#' logger.start("Tests for Significance")
#' logger.completed()
#' logger.close()
#' }
#' @section Details:
#' \code{logger.start} initializes the logger and/or starts a new section. \code{logger.completed} completes the last
#' (innermost) open section in the log. \code{logger.close} deinitializes the logger. Note that after reinitialization
#' or deinitialization, the information about the current output file, as well as any open sections, is deleted.
#'
#' @seealso logger.isinitialized
#' @author adapted by Fabian Mueller from RnBeads code by Yassen Assenov
#' @export
logger.start <- function(txt = character(0), fname = NULL) {
	if (!logger.isinitialized()) {
		if (is.null(fname)) {
			logger.start(fname=NA) #initialize the logger to the console if not started yet
			# stop("logger is not initialized")
		}
	}
	if (!is.null(fname)) {
		if (!((length(fname) == 1 && (is.character(fname) || is.na(fname))) ||
			(length(fname) == 2 && (is.character(fname) && sum(is.na(fname)) == 1 &&
					sum(fname == "", na.rm = TRUE) == 0)))) {
			stop("invalid value for fname")
		}
		if (exists("logfiles", envir = .LOG.INFO, inherits = FALSE)) {
			logger.close()
		}
		.LOG.INFO[["memory"]] <- TRUE
		.LOG.INFO[["formatter"]] <- logger.format
		for (i in 1:length(fname)) {
			if (!is.na(fname[i])) {
				fname[i] <- normalizePath(fname[i], mustWork = FALSE)
			}
		}
		.LOG.INFO[["logfiles"]] <- as.character(fname)
		.LOG.INFO[["titles"]] <- character(0)
	}
	txt <- logger.transform(txt, indent = FALSE)
	if (length(txt) != 0) {
		logger.status(paste("STARTED", txt))
		.LOG.INFO[["titles"]] <- c(.LOG.INFO[["titles"]], txt)
	}
}

########################################################################################################################

#' @rdname loggerManagement
#' @export
logger.completed <- function() {
	if (!logger.isinitialized()) {
		stop("logger is not initialized")
	}
	N <- length(.LOG.INFO[["titles"]])
	if (length(.LOG.INFO[["titles"]]) == 0) {
		logger.error("No section to complete")
	}
	txt <- paste("COMPLETED ", .LOG.INFO[["titles"]][N], ifelse(N == 1, "\n", ""), sep = "")
	.LOG.INFO[["titles"]] <- .LOG.INFO[["titles"]][-N]
	logger.status(txt)
}

########################################################################################################################

## logger.addfile
##
## Adds a new file (or console) to contain the messages of the logger.
##
## @param fname Name of the log file. This function normalizes the given file name, that is, it converts it to an
##              absolute name. Set this to \code{NA} in order to print log messages to the console.
##
## @seealso \code{\link{logger.start}} for re-initializing the logger
##
## @author adapted by Fabian Mueller from RnBeads code by Yassen Assenov
logger.addfile <- function(fname) {
	if (!(length(fname) == 1 && (is.na(fname) || is.character(fname)))) {
		stop("invalid value for fname")
	}
	if (!logger.isinitialized()) {
		# stop("logger is not initialized")
		logger.start(fname=NA) #initialize the logger to the console if not started yet
	}
	logfiles <- get("logfiles", envir = .LOG.INFO, inherits = FALSE)
	if (!(fname %in% logfiles)) {
		if (any(sapply(logfiles, function(x) { is.character(x) && (!is.na(x)) }))) {
			## Adding a file when there is already a file
			stop("logger is already initialized to file")
		}
		.LOG.INFO[["logfiles"]] <- c(logfiles, as.character(fname))
	}
}

########################################################################################################################

#' @rdname loggerManagement
#' @export
logger.close <- function() {
	rm(list = ls(envir = .LOG.INFO), envir = .LOG.INFO)
}

########################################################################################################################

#' logger.validate.file
#'
#' Validates the specified file or directory exists. Prints an error or a warning message to the log if it does not
#' exist, it is not of the accepted type or is not accessible.
#'
#' @param file      Name of file or directory to validate.
#' @param is.file   Flag indicating if the given name must denote an existing file. If this is \code{FALSE}, the given
#'                  name must denote a directory. Set this to \code{NA} if both types are an acceptable scenario.
#' @param terminate Flag indicating if the execution is to be terminated in case the validation fails. This parameter
#'                  determines if an error message (\code{terminate} is \code{TRUE}) or a warning message
#'                  (\code{terminate} is \code{FALSE}) is to be sent to the log when the specified file or directory
#'                  does not exist, is not of the accepted type or is not accessible.
#' @return Whether the validation succeeded or not, invisibly. Note that when \code{terminate} is \code{TRUE} and the
#'         validation fails, the R session is closed and thus no value is returned.
#'
#' @examples
#' \donttest{
#' if (!logger.isinitialized())
#'   logger.start(fname = NA)
#' # Validate the current working directory exists
#' logger.validate.file(getwd(), FALSE)
#' }
#' @author adapted by Fabian Mueller from RnBeads code by Yassen Assenov
#' @export
logger.validate.file <- function(file, is.file = TRUE, terminate = TRUE) {
	if (!(is.character(file) && length(file) == 1 && (!is.na(file)))) {
		stop("invalid value for file; expected single character")
	}
	if (!parameter.is.flag(is.file)) {
		stop("invalid value for is.file; expected TRUE or FALSE")
	}
	if (!parameter.is.flag(terminate)) {
		stop("invalid value for terminate; expected TRUE or FALSE")
	}
	file <- file[1]
	is.file <- is.file[1]
	terminate <- terminate[1]
	if (!file.exists(file)) {
		msg <- ifelse(is.na(is.file), "File / directory", ifelse(is.file, "File", "Directory"))
		msg <- c(msg, "not found:", file)
		if (terminate) {
			logger.error(msg)
		}
		logger.warning(msg)
		return(invisible(FALSE))
	}
	if (!is.na(is.file)) {
		is.dir <- file.info(file)[1, "isdir"]
		if (is.file == is.dir) {
			msg <- c(file, "is a", ifelse(is.dir, "directory", "file"))
			if (terminate) {
				logger.error(msg)
			}
			logger.warning(msg)
			return(invisible(FALSE))
		}
	}
	return(invisible(TRUE))
}
