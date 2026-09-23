# Interpreting results

## Errors

| Finding | Usual cause | Fix |
|---|---|---|
| `broken remote image (HTTP 404)` on `storage.googleapis.com` | The object was never uploaded to that path, or it was moved. The bucket returns `NoSuchKey`. | Look for the same image under another known path in the bucket. Either upload it to the referenced path or point the doc at the working URL. |
| `broken remote image (HTTP 403)` | The object exists but is not publicly readable. | Grant public read on the object or bucket, or move it to a public path. |
| `local image not found` | Wrong relative path, or the image file was not committed. | Fix the path or add the file. |
| `internal link target not found` | The target page was renamed or moved. | Find the new path in the docs tree or sitemap and update the link. |
| `broken link (HTTP 404)` in `live` mode | Same as above, seen from the published site. | Update the link in the source, or add a redirect. |
| `page failed to load` | The sitemap lists a page that errors or no longer exists. | Remove it from navigation or restore the page. |
| `HTTP 429` or `ERR TimeoutError` | Rate limiting or a slow host. | Rerun before reporting. Treat as unconfirmed if it persists only for one host. |

## Warnings

| Finding | Usual cause | Fix |
|---|---|---|
| `text promises a diagram/image but none follows` | The image line was dropped, often while moving content into a snippet or shared include. | Restore the image, or reword the sentence. |
| `image has no alt text` | `![](url)` with empty brackets. | Add short descriptive alt text. Low priority. |

## Example

A page reads "The diagram below depicts the target topology for GCP." and the
image under it is blank. The `<img>` tag is present in the HTML, so the Markdown
rendered correctly. Checking the image URL directly returns HTTP 404
`NoSuchKey`: the file is missing from the bucket. The fix is in storage or the
image URL, not in the page layout.
