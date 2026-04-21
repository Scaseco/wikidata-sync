#!/usr/bin/env groovy

/*
 * This groovy script checks for latest truthy and lexemes downloads from Wikidata.
 * Outputs the result as JSON using Google's Gson library.
 *
 * Usage: wikidata-release-status.groovy [baseUrl] [--since YYYYMMDD]
 *   baseUrl           Base URL for Wikidata dumps (default: https://dumps.wikimedia.org/wikidatawiki/entities/)
 *   --since YYYYMMDD  Only include entries after the given date (exclusive)
 *                     Results sorted chronologically (oldest first).
 *                     Without this flag, results sorted reverse chronologically (newest first).
 */

@Grab(group='org.jsoup', module='jsoup', version='1.16.1')
@Grab(group='com.google.code.gson', module='gson', version='2.10.1')
@Grab(group='info.picocli', module='picocli-groovy', version='4.7.7')
import org.jsoup.Jsoup
import com.google.gson.GsonBuilder
import com.google.gson.JsonObject
import com.google.gson.JsonArray
import groovy.transform.Field
import picocli.groovy.PicocliScript
import picocli.CommandLine.Parameters
import picocli.CommandLine.Option
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@PicocliScript

@Field def dateFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")

@Option(names = ["--since"], description = "Only include entries after the given date (exclusive)")
@Field String since

@Parameters(index = "0", defaultValue = "https://dumps.wikimedia.org/wikidatawiki/entities/", description = "Base URL for Wikidata dumps")
@Field String baseUrl

def findAllDumps(JsonObject outJsonObject, List<String> baseNames, String baseUrl, LocalDate since) {
    def indexPage = Jsoup.connect(baseUrl).get()

    def dateDirs = indexPage.select("a[href~=[0-9]{8}/]")
        .collect { it.text().replace("/", "") }
        .findAll { it ==~ /\d{8}/ }
        .collect { LocalDate.parse(it, dateFormatter) }
        .sort()

    def fileDatePattern = ~/(?<=wikidata-)\d{8}(?=-[^.]+\.nt\.bz2)/

    Map<String, List<List>> filesByBaseName = baseNames.collectEntries { [it, []] }

    for (date in dateDirs) {
        def dateStr = date.format(dateFormatter)
        def subUrl = "${baseUrl}${dateStr}/"
        def subPage = Jsoup.connect(subUrl).get()

        subPage.select("a[href]").each { link ->
            def href = link.attr("href")
            if (!href.endsWith(".nt.bz2")) return
            def matcher = (href =~ fileDatePattern)
            if (!matcher.find()) return

            def fileDateStr = matcher.group()
            def fileDate = LocalDate.parse(fileDateStr, dateFormatter)

            if (since != null && !fileDate.isAfter(since)) return

            baseNames.each { baseName ->
                def expectedFile = "wikidata-${fileDateStr}-${baseName}.nt.bz2"
                if (href == expectedFile) {
                    filesByBaseName[baseName] << [fileDate, "${subUrl}${href}"]
                }
            }
        }
    }

    filesByBaseName.each { baseName, fileList ->
        fileList.sort { it.first }
        fileList.each { fileDate, url ->
            JsonObject r = new JsonObject()
            r.addProperty("date", fileDate.format(dateFormatter))
            r.addProperty("url", url)
            outJsonObject.getAsJsonArray(baseName).add(r)
        }
    }
}

def sinceDate = since != null ? LocalDate.parse(since, dateFormatter) : null

def baseNames = ["truthy-BETA", "lexemes-BETA"]

def jsonObject = new JsonObject()
baseNames.each { jsonObject.add(it, new JsonArray()) }

findAllDumps(jsonObject, baseNames, baseUrl, sinceDate)

def gson = new GsonBuilder().setPrettyPrinting().create()
println gson.toJson(jsonObject)

