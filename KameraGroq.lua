require "import"
import "android.hardware.Camera"
import "android.view.SurfaceView"
import "android.view.SurfaceHolder"
import "android.view.ViewGroup"
import "android.view.View"
import "android.view.Gravity"
import "android.view.WindowManager"
import "android.view.KeyEvent"
import "android.widget.FrameLayout"
import "android.widget.LinearLayout"
import "android.widget.Button"
import "android.widget.EditText"
import "android.graphics.Color"
import "android.graphics.Bitmap"
import "android.graphics.BitmapFactory"
import "android.graphics.Matrix"
import "android.app.AlertDialog"
import "android.content.Context"
import "android.content.DialogInterface"
import "android.content.ClipData"
import "android.content.ClipboardManager"
import "android.os.Handler"
import "android.os.Looper"
import "android.os.Vibrator"
import "android.util.Base64"
import "java.io.ByteArrayOutputStream"
import "java.io.File"
import "java.io.FileOutputStream"
import "java.net.URL"
import "java.net.HttpURLConnection"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.lang.System"
import "java.lang.String"
import "java.lang.Runnable"
import "java.lang.Thread"
import "java.util.HashMap"
import "org.json.JSONObject"
import "org.json.JSONArray"
import "com.androlua.Http"

local mainHandler = Handler(Looper.getMainLooper())
local vibrator = service.getSystemService(Context.VIBRATOR_SERVICE)

-- ====================================================================
-- HELPER TAMPILAN DIALOG OVERLAY
-- ====================================================================
local function displayOverlayDialog(builder)
  local dlg = builder.create()
  local win = dlg.getWindow()
  if win then
    win.setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  end
  dlg.show()
  return dlg
end

-- ====================================================================
-- KONFIGURASI VERSI & GITHUB AUTO-UPDATE
-- ====================================================================
local APP_TITLE = "Deskripsi kamera Groq by Novan"
local CURRENT_VERSION = "1.0.3"
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/novanblind/DeskripsikameraGroq/main/KameraGroq.lua"

local MODEL_NAME = "qwen/qwen3.8-27b"

local DEFAULT_TEXT_INSTRUCTION = "Salin dan tulis ulang seluruh teks yang terbaca pada gambar ini secara presisi dari atas ke bawah sesuai urutan aslinya. Jangan tambahkan deskripsi visual, jangan berikan kesimpulan, dan jangan gunakan kata pengantar. Tampilkan HANYA teks mentah yang terlihat di layar."
local DEFAULT_MONEY_INSTRUCTION = "Identifikasi nominal uang tunai kertas atau koin rupiah pada gambar ini. Berikan HANYA nominal uangnya saja dalam bahasa Indonesia secara singkat dan jelas, contoh: Seratus ribu rupiah, Lima puluh ribu rupiah, Dua puluh ribu rupiah, Sepuluh ribu rupiah, Lima ribu rupiah, Dua ribu rupiah, Seribu rupiah, atau Uang tidak terdeteksi. DILARANG memberikan pengantar, akhiran, ataupun penjelasan visual tambahan."
local DEFAULT_PHOTO_DESC_INSTRUCTION = [[DILARANG KERAS menggunakan kalimat pengantar, pembuka, atau basa-basi apa pun seperti 'Berdasarkan gambar...', 'Berikut adalah...', 'Gambar ini memperlihatkan...', atau sejenisnya. 

LANGSUNG mulai kata pertama dengan menyebutkan objek utama yang terlihat. Deskripsikan gambar secara jelas, natural, dan profesional dalam bahasa Indonesia. Susun narasi visual yang mengalir dari elemen paling dominan ke objek, karakter, lingkungan, dan detail sekitarnya. Jelaskan warna, bentuk, ukuran, tekstur, posisi, pencahayaan, suasana, komposisi, serta hubungan antarelemen tanpa berlebihan.
Jika terdapat manusia atau karakter, gambarkan penampilan, pakaian, ekspresi, arah pandangan, gestur, dan kesan emosional yang tampak. Jelaskan pula kedalaman ruang, objek di depan, tengah, dan belakang, serta cara komposisi mengarahkan perhatian.

Jika gambar berisi surat, dokumen, formulir, poster, papan, atau teks lainnya, bacakan dan transkripsikan seluruh teks yang terlihat secara akurat. Pertahankan urutan pembacaan sesuai tata letak gambar.

Jangan gunakan pembuka umum seperti 'Gambar ini menunjukkan...', penomoran, bullet point, subjudul, atau kategori. Dasarkan setiap pernyataan pada hal yang benar-benar terlihat; nyatakan ketidakpastian jika diperlukan. Pastikan isi surat atau dokumen disampaikan secara lengkap sebelum memberikan deskripsi visual dan kesan suasana keseluruhan.]]

local sp = service.getSharedPreferences("novan_groq_camera_desc_config", Context.MODE_PRIVATE)

-- ====================================================================
-- DETEKSI JALUR BERKAS SCRIPT LOKAL
-- ====================================================================
local function getScriptFilePath()
  local src = debug.getinfo(1, "S").source
  if src and src:sub(1, 1) == "@" then
    return src:sub(2)
  end
  local fallbackPaths = {
    "/storage/emulated/0/解说/Plugin/Deskripsi kamera Groq by Novan/main.lua",
    "/sdcard/解说/Plugin/Deskripsi kamera Groq by Novan/main.lua",
    "/storage/emulated/0/jieshuo/plugin/Deskripsi kamera Groq by Novan/main.lua",
    "/sdcard/jieshuo/plugin/Deskripsi kamera Groq by Novan/main.lua"
  }
  for _, path in ipairs(fallbackPaths) do
    if File(path).exists() then return path end
  end
  return fallbackPaths[1]
end

-- ====================================================================
-- MEKANISME AUTO-UPDATE DENGAN DIALOG NOTIFIKASI
-- ====================================================================
local function parseVersion(verStr)
  local parts = {}
  for num in string.gmatch(verStr or "", "(%d+)") do
    table.insert(parts, tonumber(num))
  end
  return parts
end

local function isNewerVersion(remoteVer, localVer)
  local r = parseVersion(remoteVer)
  local l = parseVersion(localVer)
  local maxLen = math.max(#r, #l)
  for i = 1, maxLen do
    local rNum = r[i] or 0
    local lNum = l[i] or 0
    if rNum > lNum then return true end
    if rNum < lNum then return false end
  end
  return false
end

local function saveNewScript(newCode, targetPath)
  local success = false
  pcall(function()
    local f = File(targetPath)
    if not f.getParentFile().exists() then
      f.getParentFile().mkdirs()
    end
    local fos = FileOutputStream(f)
    fos.write(String(newCode).getBytes("UTF-8"))
    fos.flush()
    fos.close()
    success = true
  end)
  return success
end

local function showDownloadSuccessDialog(newVer)
  mainHandler.post(Runnable{
    run = function()
      service.speak("Download selesai. Pembaruan versi " .. newVer .. " berhasil disimpan.")
      local b = AlertDialog.Builder(service)
        .setTitle("Download Selesai")
        .setMessage("Pembaruan ke versi " .. newVer .. " berhasil diunduh dan dipasang.\n\nSilakan muat ulang atau buka kembali plugin untuk menerapkan perubahan.")
        .setPositiveButton("Oke", function(dlg, which)
          if dlg then dlg.dismiss() end
        end)
      displayOverlayDialog(b)
    end
  })
end

local function showUpdateAvailableDialog(remoteVersion, newCode)
  mainHandler.post(Runnable{
    run = function()
      service.speak("Versi baru tersedia: " .. remoteVersion .. ". Versi yang sedang digunakan: " .. CURRENT_VERSION)
      local b = AlertDialog.Builder(service)
        .setTitle("Versi Baru Tersedia")
        .setMessage("Versi Baru: v" .. remoteVersion .. "\nVersi yang Sedang Digunakan: v" .. CURRENT_VERSION .. "\n\nApakah Anda ingin memperbarui sekarang?")
        .setPositiveButton("Perbarui", function(dlg, which)
          if dlg then dlg.dismiss() end
          service.speak("Sedang mengunduh dan memasang pembaruan...")
          Thread(Runnable{
            run = function()
              local localPath = getScriptFilePath()
              if localPath and saveNewScript(newCode, localPath) then
                showDownloadSuccessDialog(remoteVersion)
              else
                mainHandler.post(Runnable{
                  run = function()
                    service.speak("Gagal menyimpan berkas pembaruan.")
                  end
                })
              end
            end
          }).start()
        end)
        .setNegativeButton("Nanti", function(dlg, which)
          if dlg then dlg.dismiss() end
        end)
      displayOverlayDialog(b)
    end
  })
end

local function checkForUpdate()
  local fetchUrl = GITHUB_RAW_URL .. "?t=" .. tostring(os.time())

  local function processUpdateContent(content)
    if not content or #content < 200 then return end
    local remoteVersion = content:match('local%s+CURRENT_VERSION%s*=%s*["\']([^"\']+)["\']')
    if remoteVersion and isNewerVersion(remoteVersion, CURRENT_VERSION) then
      showUpdateAvailableDialog(remoteVersion, content)
    end
  end

  local httpEngine = http or Http
  if httpEngine and httpEngine.get then
    pcall(function()
      httpEngine.get(fetchUrl, function(code, content)
        if code == 200 then
          processUpdateContent(content)
        end
      end)
    end)
  else
    Thread(Runnable{
      run = function()
        pcall(function()
          local url = URL(fetchUrl)
          local conn = url.openConnection()
          conn.setRequestMethod("GET")
          conn.setConnectTimeout(8000)
          conn.setReadTimeout(10000)
          conn.setInstanceFollowRedirects(true)

          if conn.getResponseCode() == 200 then
            local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
            local lines = {}
            local line = reader.readLine()
            while line ~= nil do
              table.insert(lines, line)
              line = reader.readLine()
            end
            reader.close()
            processUpdateContent(table.concat(lines, "\n"))
          end
          conn.disconnect()
        end)
      end
    }).start()
  end
end

-- ====================================================================
-- SISTEM PEMBACAAN FILE API KEY DARI PENYIMPANAN INTERNAL
-- ====================================================================
local function readLocalApiKeyFile()
  local candidatePaths = {
    "/storage/emulated/0/解说/Plugin/Deskripsi kamera Groq by Novan/api_key.txt",
    "/sdcard/解说/Plugin/Deskripsi kamera Groq by Novan/api_key.txt",
    "/storage/emulated/0/jieshuo/plugin/Deskripsi kamera Groq by Novan/api_key.txt",
    "/sdcard/jieshuo/plugin/Deskripsi kamera Groq by Novan/api_key.txt"
  }

  local src = debug.getinfo(1, "S").source
  if src and src:sub(1, 1) == "@" then
    local scriptDir = src:sub(2):match("(.*/)")
    if scriptDir then
      table.insert(candidatePaths, 1, scriptDir .. "api_key.txt")
    end
  end

  for _, path in ipairs(candidatePaths) do
    local fObj = File(path)
    if fObj.exists() and fObj.isFile() then
      local f = io.open(path, "r")
      if f then
        local content = f:read("*all")
        f:close()
        if content then
          local key = content:gsub("^%s*(.-)%s*$", "%1")
          if key ~= "" then return key end
        end
      end
    end
  end
  return ""
end

local function getActiveApiKey()
  local customKey = sp.getString("custom_api_key", "")
  if customKey ~= "" then return customKey end

  return readLocalApiKeyFile()
end

local currentMode = sp.getString("app_mode", "desc")
local cameraFacing = sp.getString("camera_facing", "environment")
local selectedResolution = sp.getString("resolution", "720p")
local vibrationEnabled = sp.getBoolean("vibrate_enabled", true)
local torchEnabled = sp.getBoolean("torch_enabled", false)

local textInstruction = sp.getString("instruction_text", DEFAULT_TEXT_INSTRUCTION)
local moneyInstruction = sp.getString("instruction_money", DEFAULT_MONEY_INSTRUCTION)
local photoDescInstruction = sp.getString("instruction_desc", DEFAULT_PHOTO_DESC_INSTRUCTION)

local cam = nil
local dialog = nil
local currentHolder = nil
local isCapturing = false
local lastOcrResult = ""

local btnModeTextRef = nil
local btnModeMoneyRef = nil
local btnModeDescRef = nil

local function triggerHaptic(ms)
  if not vibrationEnabled then return end
  pcall(function()
    if vibrator and vibrator.hasVibrator() then
      vibrator.vibrate(ms)
    end
  end)
end

-- ====================================================================
-- MANAJEMEN HARDWARE KAMERA STANDAR ANDROID
-- ====================================================================
local function getCameraId(facingType)
  local targetFacing = (facingType == "user") and Camera.CameraInfo.CAMERA_FACING_FRONT or Camera.CameraInfo.CAMERA_FACING_BACK
  local count = Camera.getNumberOfCameras()
  local info = Camera.CameraInfo()
  for i = 0, count - 1 do
    Camera.getCameraInfo(i, info)
    if info.facing == targetFacing then
      return i
    end
  end
  return 0
end

local function releaseCamera()
  if cam then
    pcall(function()
      cam.stopPreview()
      cam.release()
    end)
    cam = nil
  end
end

local function applyTorchState(enable)
  if not cam or cameraFacing == "user" then return end
  pcall(function()
    local params = cam.getParameters()
    local modes = params.getSupportedFlashModes()
    if modes and modes.contains(Camera.Parameters.FLASH_MODE_TORCH) then
      params.setFlashMode(enable and Camera.Parameters.FLASH_MODE_TORCH or Camera.Parameters.FLASH_MODE_OFF)
      cam.setParameters(params)
    end
  end)
end

local function startCameraPreview(holder)
  if not holder then return end
  releaseCamera()

  pcall(function()
    local camId = getCameraId(cameraFacing)
    cam = Camera.open(camId)
    cam.setDisplayOrientation(90)
    cam.setPreviewDisplay(holder)

    local params = cam.getParameters()
    if cameraFacing == "user" then
      params.setRotation(270)
    else
      params.setRotation(90)
    end

    local modes = params.getSupportedFlashModes()
    if modes and modes.contains(Camera.Parameters.FLASH_MODE_TORCH) then
      params.setFlashMode(torchEnabled and Camera.Parameters.FLASH_MODE_TORCH or Camera.Parameters.FLASH_MODE_OFF)
    end

    cam.setParameters(params)
    cam.startPreview()
    service.speak("Kamera aktif. Siap mengambil foto.")
  end)
end

-- ====================================================================
-- PROSES GAMBAR KE BASE64
-- ====================================================================
local function processCapturedData(data)
  local origBmp = BitmapFactory.decodeByteArray(data, 0, #data)
  if not origBmp then return nil end

  local matrix = Matrix()
  local rotAngle = (cameraFacing == "user") and 270 or 90
  matrix.postRotate(rotAngle)

  local rotatedBmp = Bitmap.createBitmap(origBmp, 0, 0, origBmp.getWidth(), origBmp.getHeight(), matrix, true)
  pcall(function() origBmp.recycle() end)

  local limit = 720
  local quality = 75

  if selectedResolution == "4k" or selectedResolution == "original" then
    limit = 0
    quality = 85
  elseif selectedResolution == "1080p" then
    limit = 1080
    quality = 80
  elseif selectedResolution == "720p" then
    limit = 720
    quality = 75
  elseif selectedResolution == "480p" then
    limit = 480
    quality = 70
  elseif selectedResolution == "360p" then
    limit = 360
    quality = 65
  end

  local w = rotatedBmp.getWidth()
  local h = rotatedBmp.getHeight()
  local minSide = math.min(w, h)
  local targetBmp = rotatedBmp
  local needRecycle = false

  if limit > 0 and minSide > limit then
    local scale = limit / minSide
    local newW = math.max(1, math.floor(w * scale))
    local newH = math.max(1, math.floor(h * scale))
    targetBmp = Bitmap.createScaledBitmap(rotatedBmp, newW, newH, true)
    needRecycle = true
  end

  local baos = ByteArrayOutputStream()
  targetBmp.compress(Bitmap.CompressFormat.JPEG, quality, baos)
  local bytes = baos.toByteArray()
  baos.close()

  local base64Str = Base64.encodeToString(bytes, Base64.NO_WRAP)

  if needRecycle then
    pcall(function() targetBmp.recycle() end)
  end
  pcall(function() rotatedBmp.recycle() end)

  return base64Str
end

-- ====================================================================
-- GROQ API ASINKRON (NON-BLOCKING DENGAN 3X RETRY)
-- ====================================================================
local function sendToGroq(base64Image)
  local activeKey = getActiveApiKey()

  if activeKey == "" then
    isCapturing = false
    service.speak("Kunci API belum ditemukan. Pastikan berkas api_key.txt sudah terisi kunci Groq.")
    return
  end

  local activeInstruction = photoDescInstruction
  local userPrompt = "Langsung sebutkan objek utama dan rincian visual gambar ini tanpa kata pengantar atau pembuka apa pun."

  if currentMode == "text" then
    activeInstruction = textInstruction
    userPrompt = "Salin seluruh teks yang tampak pada gambar ini sesuai posisi aslinya."
  elseif currentMode == "money" then
    activeInstruction = moneyInstruction
    userPrompt = "Sebutkan hanya nominal uang rupiah pada gambar ini."
  end

  local jsonPayload = JSONObject()
  jsonPayload.put("model", MODEL_NAME)
  jsonPayload.put("temperature", 0.1)
  jsonPayload.put("max_tokens", 2000)

  local messagesArray = JSONArray()

  local sysObj = JSONObject()
  sysObj.put("role", "system")
  sysObj.put("content", activeInstruction)
  messagesArray.put(sysObj)

  local userObj = JSONObject()
  userObj.put("role", "user")
  local contentArr = JSONArray()

  local textItem = JSONObject()
  textItem.put("type", "text")
  textItem.put("text", userPrompt)
  contentArr.put(textItem)

  local imgItem = JSONObject()
  imgItem.put("type", "image_url")
  local urlObj = JSONObject()
  urlObj.put("url", "data:image/jpeg;base64," .. base64Image)
  imgItem.put("image_url", urlObj)
  contentArr.put(imgItem)

  userObj.put("content", contentArr)
  messagesArray.put(userObj)
  jsonPayload.put("messages", messagesArray)

  local payloadStr = jsonPayload.toString()
  local endpoint = "https://api.groq.com/openai/v1/chat/completions"

  local headerMap = HashMap()
  headerMap.put("Content-Type", "application/json; charset=UTF-8")
  headerMap.put("Authorization", "Bearer " .. activeKey)

  local maxRetries = 3
  local attempt = 0

  local function executeRequest()
    attempt = attempt + 1

    local function handleResult(code, content)
      mainHandler.post(Runnable{
        run = function()
          isCapturing = false
          if code == 200 and content and #content > 0 then
            local ok, parseErr = pcall(function()
              local resObj = JSONObject(content)
              local choices = resObj.optJSONArray("choices")
              if choices and choices.length() > 0 then
                local choiceMsg = choices.getJSONObject(0).optJSONObject("message")
                if choiceMsg then
                  local reply = choiceMsg.optString("content")
                  lastOcrResult = reply
                  service.speak(reply)
                  return
                end
              end
              error("Respon kosong")
            end)
            if ok then return end
          end

          if attempt < maxRetries then
            mainHandler.postDelayed(Runnable{
              run = function()
                executeRequest()
              end
            }, 1500)
          else
            local errMsg = "Gagal memproses gambar setelah " .. attempt .. " kali percobaan."
            if content then
              pcall(function()
                local errObj = JSONObject(content).optJSONObject("error")
                if errObj then
                  errMsg = "Gagal: " .. errObj.optString("message")
                end
              end)
            end
            service.speak(errMsg)
          end
        end
      })
    end

    local httpEngine = http or Http
    local dispatched = false

    if httpEngine and httpEngine.post then
      local ok = pcall(function()
        httpEngine.post(endpoint, payloadStr, headerMap, function(code, content)
          handleResult(code, content)
        end)
      end)
      if ok then dispatched = true end
    end

    if not dispatched then
      Thread(Runnable{
        run = function()
          local resCode = 0
          local resContent = nil
          pcall(function()
            local url = java.net.URL(endpoint)
            local conn = url.openConnection()
            conn.setRequestMethod("POST")
            conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
            conn.setRequestProperty("Authorization", "Bearer " .. activeKey)
            conn.setDoOutput(true)
            conn.setDoInput(true)
            conn.setConnectTimeout(12000)
            conn.setReadTimeout(25000)

            local os = conn.getOutputStream()
            os.write(String(payloadStr).getBytes("UTF-8"))
            os.flush()
            os.close()

            resCode = conn.getResponseCode()
            local stream = (resCode == 200) and conn.getInputStream() or conn.getErrorStream()
            if stream then
              local reader = java.io.BufferedReader(java.io.InputStreamReader(stream, "UTF-8"))
              local lines = {}
              local line = reader.readLine()
              while line ~= nil do
                table.insert(lines, line)
                line = reader.readLine()
              end
              reader.close()
              resContent = table.concat(lines, "\n")
            end
            conn.disconnect()
          end)
          handleResult(resCode, resContent)
        end
      }).start()
    end
  end

  executeRequest()
end

-- ====================================================================
-- PEMOTRETAN FOTO
-- ====================================================================
local function captureAndProcess()
  if isCapturing or not cam then return end

  if getActiveApiKey() == "" then
    service.speak("Kunci API belum ditemukan. Pastikan file api_key.txt sudah terisi.")
    return
  end

  isCapturing = true
  triggerHaptic(80)

  local msg = "Mendeskripsikan foto..."
  if currentMode == "text" then
    msg = "Sedang memproses teks..."
  elseif currentMode == "money" then
    msg = "Mendeteksi uang..."
  end
  service.speak(msg)

  pcall(function()
    cam.takePicture(
      Camera.ShutterCallback{
        onShutter = function()
          triggerHaptic(60)
        end
      },
      nil,
      Camera.PictureCallback{
        onPictureTaken = function(data, cameraInstance)
          pcall(function()
            cameraInstance.startPreview()
            applyTorchState(torchEnabled)
          end)

          Thread(Runnable{
            run = function()
              local base64Image = processCapturedData(data)
              mainHandler.post(Runnable{
                run = function()
                  if base64Image then
                    sendToGroq(base64Image)
                  else
                    isCapturing = false
                    service.speak("Gagal memproses gambar foto.")
                  end
                end
              })
            end
          }).start()
        end
      }
    )
  end)
end

-- ====================================================================
-- MANAJEMEN MODE
-- ====================================================================
local function updateModeButtonsVisual()
  if btnModeTextRef then
    btnModeTextRef.setBackgroundColor(currentMode == "text" and Color.parseColor("#2563EB") or Color.parseColor("#1E293B"))
    btnModeTextRef.setText(currentMode == "text" and "[Aktif] Mode Teks" or "Mode Teks")
  end
  if btnModeMoneyRef then
    btnModeMoneyRef.setBackgroundColor(currentMode == "money" and Color.parseColor("#2563EB") or Color.parseColor("#1E293B"))
    btnModeMoneyRef.setText(currentMode == "money" and "[Aktif] Mode Uang" or "Mode Uang")
  end
  if btnModeDescRef then
    btnModeDescRef.setBackgroundColor(currentMode == "desc" and Color.parseColor("#2563EB") or Color.parseColor("#1E293B"))
    btnModeDescRef.setText(currentMode == "desc" and "[Aktif] Deskripsi Foto" or "Deskripsi Foto")
  end
end

local function setAppMode(m, announceText)
  currentMode = m
  sp.edit().putString("app_mode", m).apply()
  updateModeButtonsVisual()
  triggerHaptic(50)
  service.speak(announceText)
end

-- ====================================================================
-- DIALOG PENGATURAN LENGKAP
-- ====================================================================
local showSettingsMenu

local function showCameraSelectionDialog()
  local options = { "Kamera Belakang (Bawaan)", "Kamera Depan" }
  local sel = (cameraFacing == "user") and 1 or 0

  local b = AlertDialog.Builder(service)
    .setTitle("Kamera yang Digunakan")
    .setSingleChoiceItems(options, sel, function(dlg, which)
      dlg.dismiss()
      cameraFacing = (which == 1) and "user" or "environment"
      sp.edit().putString("camera_facing", cameraFacing).apply()
      if currentHolder then startCameraPreview(currentHolder) end
      service.speak(which == 1 and "Beralih ke Kamera Depan." or "Beralih ke Kamera Belakang.")
    end)
    .setNegativeButton("Batal", nil)
  displayOverlayDialog(b)
end

local function showResolutionDialog()
  local options = {
    "4K UHD (3840 x 2160)",
    "Full HD 1080p (1920 x 1080)",
    "HD 720p (1280 x 720) - Bawaan",
    "SD 480p (854 x 480)",
    "Rendah 360p (640 x 360)"
  }
  local values = { "4k", "1080p", "720p", "480p", "360p" }
  local sel = 2
  for idx, v in ipairs(values) do
    if v == selectedResolution then sel = idx - 1 break end
  end

  local b = AlertDialog.Builder(service)
    .setTitle("Resolusi Gambar")
    .setSingleChoiceItems(options, sel, function(dlg, which)
      dlg.dismiss()
      selectedResolution = values[which + 1]
      sp.edit().putString("resolution", selectedResolution).apply()
      service.speak("Resolusi diubah ke " .. options[which + 1])
    end)
    .setNegativeButton("Batal", nil)
  displayOverlayDialog(b)
end

local function showApiKeyDialog()
  local currentCustomKey = sp.getString("custom_api_key", "")
  local input = EditText(service)
  input.setSingleLine(true)

  if currentCustomKey ~= "" then
    input.setText(currentCustomKey)
    input.setHint("Kunci kustom aktif tersimpan")
  else
    input.setText("")
    input.setHint("Kunci bawaan aktif. Tempel kunci kustom di sini...")
  end

  local b = AlertDialog.Builder(service)
    .setTitle("Pengaturan Kunci API")
    .setView(input)
    .setPositiveButton("Simpan", function()
      local key = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      if key ~= "" then
        sp.edit().putString("custom_api_key", key).apply()
        service.speak("Kunci API kustom berhasil disimpan.")
      else
        sp.edit().remove("custom_api_key").apply()
        service.speak("Kunci kustom dihapus, kembali ke kunci bawaan.")
      end
    end)
    .setNeutralButton("Reset Kunci API", function()
      sp.edit().remove("custom_api_key").apply()
      if readLocalApiKeyFile() ~= "" then
        service.speak("Kunci API berhasil di-reset ke berkas bawaan.")
      else
        service.speak("Kunci API di-reset. Silakan pastikan file api_key.txt terisi.")
      end
    end)
    .setNegativeButton("Batal", nil)

  displayOverlayDialog(b)
end

local function showEditInstructionDialog(title, defaultVal, currentVal, saveKey)
  local input = EditText(service)
  input.setText(currentVal)
  input.setMinLines(5)

  local b = AlertDialog.Builder(service)
    .setTitle(title)
    .setView(input)
    .setPositiveButton("Simpan", function()
      local text = tostring(input.getText()):gsub("^%s*(.-)%s*$", "%1")
      if text == "" then text = defaultVal end
      sp.edit().putString(saveKey, text).apply()
      if saveKey == "instruction_text" then textInstruction = text end
      if saveKey == "instruction_money" then moneyInstruction = text end
      if saveKey == "instruction_desc" then photoDescInstruction = text end
      service.speak("Instruksi berhasil disimpan.")
    end)
    .setNeutralButton("Reset Default", function()
      sp.edit().putString(saveKey, defaultVal).apply()
      if saveKey == "instruction_text" then textInstruction = defaultVal end
      if saveKey == "instruction_money" then moneyInstruction = defaultVal end
      if saveKey == "instruction_desc" then photoDescInstruction = defaultVal end
      service.speak("Instruksi dikembalikan ke default.")
    end)
    .setNegativeButton("Batal", nil)
  displayOverlayDialog(b)
end

showSettingsMenu = function()
  local camText = (cameraFacing == "user") and "Depan" or "Belakang"
  local vibText = vibrationEnabled and "Aktif" or "Mati"
  local torchText = torchEnabled and "Aktif" or "Mati"

  local items = {
    "1. Kamera yang Digunakan (" .. camText .. ")",
    "2. Resolusi Gambar (" .. selectedResolution .. ")",
    "3. Pengaturan Kunci API",
    "4. Lampu Flash Kamera (" .. torchText .. ")",
    "5. Getaran Saat Memotret (" .. vibText .. ")",
    "6. Edit Instruksi Mode Teks",
    "7. Edit Instruksi Mode Uang",
    "8. Edit Instruksi Deskripsi Foto",
    "9. Reset Seluruh Pengaturan ke Bawaan"
  }

  local b = AlertDialog.Builder(service)
    .setTitle("Pengaturan - " .. APP_TITLE .. " v" .. CURRENT_VERSION)
    .setItems(items, function(dlg, which)
      dlg.dismiss()
      if which == 0 then
        showCameraSelectionDialog()
      elseif which == 1 then
        showResolutionDialog()
      elseif which == 2 then
        showApiKeyDialog()
      elseif which == 3 then
        torchEnabled = not torchEnabled
        sp.edit().putBoolean("torch_enabled", torchEnabled).apply()
        applyTorchState(torchEnabled)
        service.speak("Lampu flash " .. (torchEnabled and "diaktifkan." or "dimatikan."))
      elseif which == 4 then
        vibrationEnabled = not vibrationEnabled
        sp.edit().putBoolean("vibrate_enabled", vibrationEnabled).apply()
        service.speak("Getaran " .. (vibrationEnabled and "diaktifkan." or "dinonaktifkan."))
      elseif which == 5 then
        showEditInstructionDialog("Instruksi Mode Teks", DEFAULT_TEXT_INSTRUCTION, textInstruction, "instruction_text")
      elseif which == 6 then
        showEditInstructionDialog("Instruksi Mode Uang", DEFAULT_MONEY_INSTRUCTION, moneyInstruction, "instruction_money")
      elseif which == 7 then
        showEditInstructionDialog("Instruksi Deskripsi Foto", DEFAULT_PHOTO_DESC_INSTRUCTION, photoDescInstruction, "instruction_desc")
      elseif which == 8 then
        sp.edit().clear().apply()
        currentMode = "desc"
        cameraFacing = "environment"
        selectedResolution = "720p"
        vibrationEnabled = true
        torchEnabled = false
        textInstruction = DEFAULT_TEXT_INSTRUCTION
        moneyInstruction = DEFAULT_MONEY_INSTRUCTION
        photoDescInstruction = DEFAULT_PHOTO_DESC_INSTRUCTION

        updateModeButtonsVisual()
        applyTorchState(false)
        if currentHolder then startCameraPreview(currentHolder) end
        service.speak("Seluruh pengaturan telah dikembalikan ke bawaan.")
      end
    end)
    .setNegativeButton("Tutup", nil)

  displayOverlayDialog(b)
end

-- ====================================================================
-- SALIN TULISAN
-- ====================================================================
local function copyLastText()
  triggerHaptic(40)
  if lastOcrResult == "" then
    service.speak("Belum ada teks yang dapat disalin.")
    return
  end
  pcall(function()
    local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
    local clip = ClipData.newPlainText("Hasil Pembacaan Groq", lastOcrResult)
    clipboard.setPrimaryClip(clip)
    service.speak("Teks berhasil disalin.")
  end)
end

-- ====================================================================
-- TAMPILAN KAMERA OVERLAY & KONTROL AKSESIBILITAS
-- ====================================================================
local function launchCameraView()
  service.speak("Membuka " .. APP_TITLE .. "...")

  local surfaceView = SurfaceView(service)
  surfaceView.setLayoutParams(ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
  surfaceView.setZOrderMediaOverlay(true)
  surfaceView.getHolder().setKeepScreenOn(true)

  local holder = surfaceView.getHolder()
  holder.addCallback(SurfaceHolder.Callback{
    surfaceCreated = function(h)
      currentHolder = h
      startCameraPreview(h)
    end,
    surfaceChanged = function(h, format, w, hgt) end,
    surfaceDestroyed = function(h)
      currentHolder = nil
      releaseCamera()
    end
  })

  local frame = FrameLayout(service)
  frame.setLayoutParams(ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
  frame.setFitsSystemWindows(true)
  frame.addView(surfaceView)

  -- Bilah Kontrol Bawah
  local bottomControls = LinearLayout(service)
  bottomControls.setOrientation(LinearLayout.VERTICAL)
  bottomControls.setBackgroundColor(Color.parseColor("#D9000000"))
  bottomControls.setPadding(20, 16, 20, 24)
  bottomControls.setGravity(Gravity.CENTER_HORIZONTAL)

  local bottomParams = FrameLayout.LayoutParams(
    ViewGroup.LayoutParams.MATCH_PARENT,
    ViewGroup.LayoutParams.WRAP_CONTENT,
    Gravity.BOTTOM
  )
  bottomControls.setLayoutParams(bottomParams)

  -- Baris 1: Tombol Ambil Foto Utama (Besar)
  local btnCapture = Button(service)
  btnCapture.setText("Ambil Foto")
  btnCapture.setTextSize(18)
  btnCapture.setTextColor(Color.BLACK)
  btnCapture.setBackgroundColor(Color.WHITE)
  btnCapture.setPadding(0, 20, 0, 20)

  local captureParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
  captureParams.setMargins(0, 0, 0, 12)
  btnCapture.setLayoutParams(captureParams)

  btnCapture.setOnClickListener(function()
    captureAndProcess()
  end)
  bottomControls.addView(btnCapture)

  -- Baris 2: Tiga Tombol Mode Sejajar
  local modeBar = LinearLayout(service)
  modeBar.setOrientation(LinearLayout.HORIZONTAL)
  modeBar.setLayoutParams(LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

  local function createModeBtn(label)
    local b = Button(service)
    b.setText(label)
    b.setTextSize(13)
    b.setTextColor(Color.WHITE)
    b.setPadding(0, 14, 0, 14)
    local p = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1)
    p.setMargins(4, 0, 4, 0)
    b.setLayoutParams(p)
    return b
  end

  btnModeTextRef = createModeBtn("Mode Teks")
  btnModeMoneyRef = createModeBtn("Mode Uang")
  btnModeDescRef = createModeBtn("Deskripsi Foto")

  btnModeTextRef.setOnClickListener(function()
    setAppMode("text", "Mode Teks diaktifkan")
  end)
  btnModeMoneyRef.setOnClickListener(function()
    setAppMode("money", "Mode Uang diaktifkan")
  end)
  btnModeDescRef.setOnClickListener(function()
    setAppMode("desc", "Mode Deskripsi Foto diaktifkan")
  end)

  modeBar.addView(btnModeTextRef)
  modeBar.addView(btnModeMoneyRef)
  modeBar.addView(btnModeDescRef)
  updateModeButtonsVisual()

  local modeBarParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
  modeBarParams.setMargins(0, 0, 0, 12)
  modeBar.setLayoutParams(modeBarParams)
  bottomControls.addView(modeBar)

  -- Baris 3: Tombol Pengaturan, Salin Tulisan, dan Kembali
  local bottomBar = LinearLayout(service)
  bottomBar.setOrientation(LinearLayout.HORIZONTAL)
  bottomBar.setLayoutParams(LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

  local function createActionBtn(label, bgColorHex)
    local b = Button(service)
    b.setText(label)
    b.setTextSize(14)
    b.setTextColor(Color.WHITE)
    b.setBackgroundColor(Color.parseColor(bgColorHex))
    b.setPadding(0, 14, 0, 14)
    local p = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1)
    p.setMargins(4, 0, 4, 0)
    b.setLayoutParams(p)
    return b
  end

  local btnSettings = createActionBtn("Pengaturan", "#334155")
  local btnCopy = createActionBtn("Salin Tulisan", "#334155")
  local btnExit = createActionBtn("Kembali", "#DC2626")

  btnSettings.setOnClickListener(function()
    showSettingsMenu()
  end)
  btnCopy.setOnClickListener(function()
    copyLastText()
  end)
  btnExit.setOnClickListener(function()
    if dialog then dialog.dismiss() end
  end)

  bottomBar.addView(btnSettings)
  bottomBar.addView(btnCopy)
  bottomBar.addView(btnExit)
  bottomControls.addView(bottomBar)

  frame.addView(bottomControls)

  local builder = AlertDialog.Builder(service)
  builder.setView(frame)
  builder.setCancelable(true)

  dialog = builder.create()

  local win = dialog.getWindow()
  if win then
    win.setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    win.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
    win.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
    win.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_VISIBLE)
  end

  dialog.setOnKeyListener(DialogInterface.OnKeyListener{
    onKey = function(d, keyCode, event)
      if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
        d.dismiss()
        return true
      end
      return false
    end
  })

  dialog.setOnDismissListener(DialogInterface.OnDismissListener{
    onDismiss = function()
      releaseCamera()
      service.speak("Kamera ditutup.")
    end
  })

  dialog.show()

  mainHandler.postDelayed(Runnable{
    run = function()
      pcall(function()
        frame.sendAccessibilityEvent(32)
        btnCapture.setFocusable(true)
        btnCapture.requestFocus()
        btnCapture.sendAccessibilityEvent(8)
        btnCapture.sendAccessibilityEvent(32768)
        btnCapture.performAccessibilityAction(64, nil)
      end)
    end
  }, 250)
end

-- ====================================================================
-- EKSEKUSI UTAMA
-- ====================================================================
launchCameraView()

mainHandler.postDelayed(Runnable{
  run = function()
    checkForUpdate()
  end
}, 1500)

return true
