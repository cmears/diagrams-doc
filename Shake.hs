import System.Directory
import Development.Shake
import Development.Shake.FilePath

obj = (".make" </>)
un = dropDirectory1

dist = ("dist" </>)

main :: IO ()
main = shake shakeOptions { shakeThreads = 2 } $ do
  want [dist "manual/diagrams-manual.html"]
  action $ requireIcons
  action $ requireStatic

  webRules
  action $ buildWeb

  -- Cheating a bit here; this rule also generates diagrams images,
  -- BUT we don't even know their names until after running xml2html,
  -- which generates diagrams-manual.html as well.  So we have to be
  -- careful to call 'requireImages' *after* running xml2html.
  dist "manual/diagrams-manual.html" *> \out -> do
    let xml = obj . un $ replaceExtension out "xml"
        exe = obj "manual/xml2html.hs.exe"
    need [xml, exe]
    system' exe [xml, "-o", obj "manual/images", out]
    requireImages

  obj "//*.xml" *> \out -> do
    let rst = un $ replaceExtension out "rst"
    need [rst]
    system' "rst2xml" ["--input-encoding=utf8", rst, out]

  obj "//*.hs.exe" *> \out -> do
    let hs = un $ dropExtension out
    need [hs]
    ghc out hs

  dist "manual/icons/*.png" *> \out -> do
    let exe = obj . un $ replaceExtension out ".hs.exe"
    need [exe]
    system' exe ["-w", "40", "-h", "40", "-o", out]

  copyFiles "manual/static"
  copyImages

  addOracle ["ghc-pkg"] $ do
    (out,_) <- systemOutput "ghc-pkg" ["list","--simple-output"]
    return $ words out

copyFiles dir = dist (dir ++ "/*") *> \out -> copyFile' (un out) out

copyImages = dist ("manual/images/*") *> \out -> copyFile' (obj . un $ out) out

requireIcons :: Action ()
requireIcons = do
  hsIcons <- getDirectoryFiles "manual/icons" "*.hs"
  let icons = map (\i -> dist $ "manual/icons" </> replaceExtension i "png") hsIcons
  need icons

requireStatic :: Action ()
requireStatic = do
  staticSrc <- getDirectoryFiles "manual/static" "*"
  let static = map (dist . ("manual/static" </>)) staticSrc
  need static

requireImages :: Action ()
requireImages = do
  images <- getDirectoryFiles (obj "manual/images") "*.png"
  let distImages = map (dist . ("manual/images" </>)) images
  need distImages

webRules :: Rules ()
webRules = do
  "web/manual" *> \out ->
    system' "ln" ["-s", "../dist/manual", out]

buildWeb :: Action ()
buildWeb = do
  alwaysRerun

  need [ "web/manual"
       , dist "manual/diagrams-manual.html"
       , obj "web/hakyll.hs.exe"
       , obj "web/gallery/Build.hs.exe"]
  requireIcons
  requireStatic
  requireImages

  systemCwd "web" (".." </> obj "web/hakyll.hs.exe") ["build"]

  -- action $ requireGallery  -- replace hakyll building with our own here

ghc out hs = do
  askOracle ["ghc-pkg"]
  let odir = takeDirectory out
  system' "ghc" ["--make", "-O2", "-outputdir", odir, "-o", out, hs]
