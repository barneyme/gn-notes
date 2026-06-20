package main

import (
	"bufio"
	"bytes"
	"crypto/md5"
	"encoding/base64"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type Config struct {
	GnUser string
	GnPass string
	GnPath string
	GnURL string
	GitToken string
	GitOwner string
	GitRepo string
	GitAPI string
}

var (
	notesDir string
	configFile string
	cfg Config
	engine string
	client = &http.Client{Timeout: 30 * time.Second}
)

func main() {
	home, _ := os.UserHomeDir()
	notesDir = filepath.Join(home, "gn")
	configFile = filepath.Join(notesDir, "gn.conf")
	os.MkdirAll(notesDir, 0700)

	loadConfig()

	if cfg.GitToken == "" && cfg.GnUser == "" {
		firstRun()
	}

	detectEngine()

	args := os.Args[1:]
	if len(args) == 0 {
		editNote("note")
		return
	}

	switch args[0] {
	case "-h", "--help":
		showHelp()
	case "-c":
		os.Remove(configFile)
		fmt.Println("Config cleared.")
	case "-s":
		syncAll()
	case "-d":
		if len(args) < 2 {
			fmt.Println("Usage: gn -d NOTE")
			return
		}
		deleteNote(args[1])
	case "-r":
		if len(args) < 3 {
			fmt.Println("Usage: gn -r OLD NEW")
			return
		}
		renameNote(args[1], args[2])
	default:
		editNote(args[0])
	}
}

func loadConfig() {
	data, err := os.ReadFile(configFile)
	if err!= nil {
		return
	}
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if i := strings.Index(line, "#"); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts)!= 2 {
			continue
		}
		k := strings.TrimSpace(parts[0])
		v := strings.TrimSpace(parts[1])
		v = strings.Trim(v, `"'`)
		switch k {
		case "gn_USER":
			cfg.GnUser = v
		case "gn_PASS":
			cfg.GnPass = v
		case "gn_PATH":
			cfg.GnPath = v
		case "gn_URL":
			cfg.GnURL = v
		case "GIT_TOKEN":
			cfg.GitToken = v
		case "GIT_OWNER":
			cfg.GitOwner = v
		case "GIT_REPO":
			cfg.GitRepo = v
		case "GIT_API":
			cfg.GitAPI = v
		}
	}
}

func saveConfig() {
	var lines []string
	if cfg.GitToken!= "" {
		lines = append(lines, "GIT_TOKEN="+cfg.GitToken)
		lines = append(lines, "GIT_OWNER="+cfg.GitOwner)
		lines = append(lines, "GIT_REPO="+cfg.GitRepo)
	} else {
		lines = append(lines, "gn_URL="+cfg.GnURL)
		lines = append(lines, "gn_USER="+cfg.GnUser)
		lines = append(lines, "gn_PASS="+cfg.GnPass)
		lines = append(lines, "gn_PATH="+cfg.GnPath)
	}
	os.WriteFile(configFile, []byte(strings.Join(lines, "\n")+"\n"), 0600)
	fmt.Println("Saved to", configFile)
}

func prompt(msg string) string {
	fmt.Print(msg + ": ")
	r := bufio.NewReader(os.Stdin)
	s, _ := r.ReadString('\n')
	return strings.TrimSpace(s)
}

func firstRun() {
	fmt.Println("No config found at", configFile, "- let's set one up.")
	fmt.Println("Select your provider:")
	fmt.Println("1) GitHub")
	fmt.Println("2) Koofr")
	choice := prompt("Choice [1-2]")
	if choice == "1" {
		cfg.GitToken = prompt("GitHub Personal Access Token")
		cfg.GitOwner = prompt("GitHub username (repo owner)")
		cfg.GitRepo = prompt("Repository name")
	} else {
		cfg.GnURL = "https://app.koofr.net/dav/Koofr"
		cfg.GnUser = prompt("Koofr email/username")
		cfg.GnPass = prompt("Koofr app password")
		p := prompt("Remote notes folder [/gn]")
		if p == "" {
			p = "/gn"
		}
		cfg.GnPath = p
	}
	if strings.ToLower(prompt("Save this config for future runs? [Y/n]"))!= "n" {
		saveConfig()
	}
}

func detectEngine() {
	if cfg.GitToken!= "" && cfg.GitOwner!= "" && cfg.GitRepo!= "" {
		engine = "GITHUB"
		if cfg.GitAPI == "" {
			cfg.GitAPI = fmt.Sprintf("https://api.github.com/repos/%s/%s/contents", cfg.GitOwner, cfg.GitRepo)
		}
	} else if cfg.GnUser!= "" && cfg.GnPass!= "" && cfg.GnURL!= "" {
		engine = "KOOFR"
		cfg.GnURL = strings.TrimRight(cfg.GnURL, "/")
		if cfg.GnPath == "" {
			cfg.GnPath = "/notes"
		}
		if!strings.HasPrefix(cfg.GnPath, "/") {
			cfg.GnPath = "/" + cfg.GnPath
		}
	} else {
		fmt.Fprintln(os.Stderr, "Error: gn.conf is incomplete.")
		os.Exit(1)
	}
}

func showHelp() {
	remote := ""
	if engine == "GITHUB" {
		remote = fmt.Sprintf("GitHub: %s/%s", cfg.GitOwner, cfg.GitRepo)
	} else {
		remote = fmt.Sprintf("Koofr: %s%s", cfg.GnURL, cfg.GnPath)
	}
	fmt.Printf(`Usage: gn [options] [note]

  -h Show this help
  -d NOTE Delete a note (local + remote)
  -r OLD NEW Rename a note (local + remote)
  -s Sync (pull) all remote notes down
  -c Clear saved credentials

Engine: %s
Remote: %s
Local: %s
`, engine, remote, notesDir)
}

func fileHash(path string) string {
	f, err := os.Open(path)
	if err!= nil {
		return ""
	}
	defer f.Close()
	h := md5.New()
	io.Copy(h, f)
	return fmt.Sprintf("%x", h.Sum(nil))
}

func editor() string {
	if e := os.Getenv("EDITOR"); e!= "" {
		return e
	}
	if runtime.GOOS == "windows" {
		return "notepad"
	}
	return "nano"
}

func sanitize(name string) string {
	if strings.Contains(name, "..") || name == "gn.conf" {
		fmt.Fprintln(os.Stderr, "Invalid name")
		os.Exit(1)
	}
	if!strings.HasSuffix(name, ".md") {
		name += ".md"
	}
	return name
}

func localPath(name string) string {
	return filepath.Join(notesDir, filepath.FromSlash(name))
}

func editNote(name string) {
	name = sanitize(name)
	pullNote(name)
	pre := fileHash(localPath(name))

	os.MkdirAll(filepath.Dir(localPath(name)), 0700)
	cmd := exec.Command(editor(), localPath(name))
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()

	if _, err := os.Stat(localPath(name)); err == nil {
		post := fileHash(localPath(name))
		if pre!= post {
			pushNote(name)
		}
	}
}

func deleteNote(name string) {
	name = sanitize(name)
	lp := localPath(name)
	if _, err := os.Stat(lp); err!= nil {
		fmt.Println("Error: not found")
		return
	}
	fmt.Printf("Delete '%s'? [y/N] ", name)
	var ans string
	fmt.Scanln(&ans)
	if strings.ToLower(ans)!= "y" {
		return
	}
	remoteDelete(name)
	os.Remove(lp)
	fmt.Println("Deleted.")
}

func renameNote(old, new string) {
	old = sanitize(old)
	new = sanitize(new)
	remoteRename(old, new)
	os.Rename(localPath(old), localPath(new))
	fmt.Println("Renamed.")
}

// --- GitHub / Koofr API ---

func ghURL(name string) string {
	return cfg.GitAPI + "/" + url.PathEscape(name)
}

func pullNote(name string) {
	lp := localPath(name)
	os.MkdirAll(filepath.Dir(lp), 0700)
	if engine == "GITHUB" {
		req, _ := http.NewRequest("GET", ghURL(name), nil)
		req.Header.Set("Authorization", "Bearer "+cfg.GitToken)
		req.Header.Set("User-Agent", "gn-go")
		resp, err := client.Do(req)
		if err!= nil {
			return
		}
		defer resp.Body.Close()
		if resp.StatusCode == 404 {
			os.Remove(lp)
			return
		}
		var data struct {
			Content string `json:"content"`
		}
		json.NewDecoder(resp.Body).Decode(&data)
		if data.Content!= "" {
			b, _ := base64.StdEncoding.DecodeString(strings.ReplaceAll(data.Content, "\n", ""))
			os.WriteFile(lp, b, 0644)
		}
	} else {
		u := koofrURL(name)
		req, _ := http.NewRequest("GET", u, nil)
		req.SetBasicAuth(cfg.GnUser, cfg.GnPass)
		resp, err := client.Do(req)
		if err!= nil {
			return
		}
		defer resp.Body.Close()
		if resp.StatusCode == 200 {
			f, _ := os.Create(lp)
			io.Copy(f, resp.Body)
			f.Close()
		} else if resp.StatusCode == 404 {
			os.Remove(lp)
		}
	}
}

func pushNote(name string) {
	lp := localPath(name)
	data, _ := os.ReadFile(lp)
	if engine == "GITHUB" {
		sha := ""
		req, _ := http.NewRequest("GET", ghURL(name), nil)
		req.Header.Set("Authorization", "Bearer "+cfg.GitToken)
		req.Header.Set("User-Agent", "gn-go")
		if resp, err := client.Do(req); err == nil && resp.StatusCode == 200 {
			var d struct{ Sha string `json:"sha"` }
			json.NewDecoder(resp.Body).Decode(&d)
			sha = d.Sha
			resp.Body.Close()
		}
		body := map[string]string{
			"message": fmt.Sprintf("gn: update %s %s", name, time.Now().Format("2006-01-02 15:04:05")),
			"content": base64.StdEncoding.EncodeToString(data),
		}
		if sha!= "" {
			body["sha"] = sha
		}
		j, _ := json.Marshal(body)
		req2, _ := http.NewRequest("PUT", ghURL(name), bytes.NewReader(j))
		req2.Header.Set("Authorization", "Bearer "+cfg.GitToken)
		req2.Header.Set("Content-Type", "application/json")
		req2.Header.Set("User-Agent", "gn-go")
		client.Do(req2)
	} else {
		dir := filepath.Dir(name)
		if dir!= "." {
			req, _ := http.NewRequest("MKCOL", koofrURL(dir), nil)
			req.SetBasicAuth(cfg.GnUser, cfg.GnPass)
			client.Do(req)
		}
		req, _ := http.NewRequest("PUT", koofrURL(name), bytes.NewReader(data))
		req.SetBasicAuth(cfg.GnUser, cfg.GnPass)
		client.Do(req)
	}
}

func remoteDelete(name string) {
	if engine == "GITHUB" {
		req, _ := http.NewRequest("GET", ghURL(name), nil)
		req.Header.Set("Authorization", "Bearer "+cfg.GitToken)
		req.Header.Set("User-Agent", "gn-go")
		resp, err := client.Do(req)
		if err!= nil || resp.StatusCode!= 200 {
			return
		}
		var d struct{ Sha string `json:"sha"` }
		json.NewDecoder(resp.Body).Decode(&d)
		resp.Body.Close()
		body, _ := json.Marshal(map[string]string{
			"message": "gn: delete " + name,
			"sha": d.Sha,
		})
		req2, _ := http.NewRequest("DELETE", ghURL(name), bytes.NewReader(body))
		req2.Header.Set("Authorization", "Bearer "+cfg.GitToken)
		req2.Header.Set("Content-Type", "application/json")
		req2.Header.Set("User-Agent", "gn-go")
		client.Do(req2)
	} else {
		req, _ := http.NewRequest("DELETE", koofrURL(name), nil)
		req.SetBasicAuth(cfg.GnUser, cfg.GnPass)
		client.Do(req)
	}
}

func remoteRename(old, new string) {
	if engine == "GITHUB" {
		data, _ := os.ReadFile(localPath(old))
		os.WriteFile(localPath(new), data, 0644)
		pushNote(new)
		remoteDelete(old)
		os.Remove(localPath(new))
	} else {
		req, _ := http.NewRequest("MOVE", koofrURL(old), nil)
		req.SetBasicAuth(cfg.GnUser, cfg.GnPass)
		req.Header.Set("Destination", koofrURL(new))
		req.Header.Set("Overwrite", "F")
		client.Do(req)
	}
}

func koofrURL(name string) string {
	p := cfg.GnPath + "/" + strings.TrimLeft(name, "/")
	parts := strings.Split(p, "/")
	for i, s := range parts {
		parts[i] = url.PathEscape(s)
	}
	return cfg.GnURL + strings.Join(parts, "/")
}

func syncAll() {
	fmt.Println("Syncing paths... [" + engine + "]")
	if engine == "GITHUB" {
		req, _ := http.NewRequest("GET", cfg.GitAPI, nil)
		req.Header.Set("Authorization", "Bearer "+cfg.GitToken)
		req.Header.Set("User-Agent", "gn-go")
		resp, _ := client.Do(req)
		defer resp.Body.Close()
		var items []struct {
			Name string `json:"name"`
			Type string `json:"type"`
		}
		json.NewDecoder(resp.Body).Decode(&items)
		for _, it := range items {
			if it.Type == "file" && strings.HasSuffix(it.Name, ".md") {
				pullNote(it.Name)
			}
		}
	} else {
		req, _ := http.NewRequest("PROPFIND", cfg.GnURL+cfg.GnPath+"/", nil)
		req.Header.Set("Depth", "infinity")
		req.SetBasicAuth(cfg.GnUser, cfg.GnPass)
		resp, _ := client.Do(req)
		defer resp.Body.Close()
		var ms struct {
			XMLName xml.Name `xml:"multistatus"`
			Resp []struct {
				Href string `xml:"href"`
			} `xml:"response"`
		}
		xml.NewDecoder(resp.Body).Decode(&ms)
		for _, r := range ms.Resp {
			h, _ := url.PathUnescape(r.Href)
			if strings.HasSuffix(h, ".md") && strings.Contains(h, cfg.GnPath) {
				rel := strings.TrimPrefix(h, cfg.GnPath+"/")
				rel = strings.TrimPrefix(rel, "/")
				if rel!= "" {
					pullNote(rel)
				}
			}
		}
	}
	fmt.Println("Sync complete.")
}